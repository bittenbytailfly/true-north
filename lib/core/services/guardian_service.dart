import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart'; 
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/guardian_state_model.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (notificationResponse.actionId == 'snooze_guilt') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String reason = prefs.getString('anchor_reason') ?? "you need to be sharp tomorrow";
       
    // Record exactly when they hit snooze
    await prefs.setInt('snooze_start_time', DateTime.now().millisecondsSinceEpoch);
    await prefs.setBool('is_snoozed', true);
    
    await _sendGuiltNotification(reason);
  }
}

Future<void> initializeGuardianService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flip = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('ic_stat_app_icon');
  await flip.initialize(
    settings: const InitializationSettings(android: androidSettings),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    NotificationConstants.persistentChannelId,
    NotificationConstants.persistentChannelName,
    description: 'This channel is used for the persistent Guardian service.',
    importance: Importance.low,
  );

  await flip.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: NotificationConstants.persistentChannelId,
      initialNotificationTitle: 'True North Active',
      initialNotificationContent: 'The Guardian is watching the clock.',
      foregroundServiceNotificationId: NotificationConstants.persistentServiceId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  bool isUrgentShowing = false;

  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final FlutterLocalNotificationsPlugin flp = FlutterLocalNotificationsPlugin();

  final state = GuardianStateModel();
  
  int minuteCounter = 0;
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('request_state').listen((event) {
    service.invoke('updateUI', state.toMap());
  });

   // --- WORKER 1: THE LOCATION STREAM (The Map) ---
  double? homeLat = prefs.getDouble('home_lat');
  double? homeLng = prefs.getDouble('home_lng');
  StreamSubscription<Position>? positionStream;

  if (homeLat != null && homeLng != null) {
    print("🛰️ [STREAM] Initializing radar stream...");
    
    // distanceFilter is the magic lag-killer. It only triggers if you move 10+ meters.
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, 
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Guardian GPS Active",
        notificationTitle: "True North",
        enableWakeLock: true,
      ),
    );

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
      double distance = Geolocator.distanceBetween(position.latitude, position.longitude, homeLat, homeLng);

      // Update the in-memory state object. No disk I/O here.
      state.polled++;
      state.distance = "${distance.toStringAsFixed(1)}m";

      if (distance <= 150.0) {
        if (!state.isHome) { // Check in-memory state
          print("🏁 [STREAM] Target Acquired. Welcome Home.");
          state.isHome = true;
          await prefs.setBool('is_home', true);
          
          // --- THE FIX: RUN ARRIVAL LOGIC DIRECTLY ---
          String landingMsg = prefs.getString('landing_message') ?? "Welcome home. The Guardian is standing down.";
          await _sendArrivalNotification(landingMsg);
          await prefs.setBool('show_arrival_popup', true);
          
          service.invoke('mission_accomplished');

          await Future.delayed(const Duration(seconds: 10));
          
          service.stopSelf(); // Kill the background service
          positionStream?.cancel(); // Kill the GPS stream
        }
      }
    });
  }

  // --- WORKER 2: THE NAG LOOP (The Clock) ---
  // Notice there is ZERO GPS logic in here now! It just runs super fast and light.
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    await prefs.reload();
    minuteCounter++; 
    
    String? targetStr = prefs.getString('target_departure_time');
    if (targetStr == null) return;

    DateTime now = DateTime.now();
    DateTime targetTime = DateTime.parse(targetStr);
    bool isPastDeadline = now.isAfter(targetTime);
    
    // --- SNOOZE WAKE-UP LOGIC ---
    if (state.isSnoozed && state.snoozeStartTime != null) {
      if (now.difference(state.snoozeStartTime!).inMinutes >= 5) {
        state.isSnoozed = false;
        state.snoozeStartTime = null;
        // Also clear from prefs in case service is killed
        await prefs.setBool('is_snoozed', false);
        await prefs.remove('snooze_start_time');
      }
    }

    // --- UPDATE PERSISTENT BACKGROUND BAR ---
    Duration diff = targetTime.difference(now);
    String countdownText = isPastDeadline 
        ? "LATE by ${diff.inMinutes.abs()}m" 
        : "Leave in: ${diff.inHours}h ${diff.inMinutes % 60}m - polled: ${state.polled}, distance: ${state.distance}";

    if (service is AndroidServiceInstance) {
      int currentProgress = 0;
      String? activationStr = prefs.getString('activation_time');
      if (activationStr != null && !isPastDeadline) {
        DateTime activationTime = DateTime.parse(activationStr);
        int totalSeconds = targetTime.difference(activationTime).inSeconds;
        int elapsedSeconds = now.difference(activationTime).inSeconds;
        if (totalSeconds > 0) currentProgress = ((elapsedSeconds / totalSeconds) * 100).toInt().clamp(0, 100);
      } else if (isPastDeadline) {
        currentProgress = 100; 
      }

      await flp.show(
        id: NotificationConstants.persistentServiceId,
        title: "Guardian Active • $countdownText",
        body: isPastDeadline ? "⚠️ MISSION CRITICAL" : "Watching your back.",
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationConstants.persistentChannelId,
            NotificationConstants.persistentChannelName,
            ongoing: true, 
            importance: Importance.defaultImportance, 
            priority: Priority.high,
            icon: 'ic_stat_app_icon', 
            showProgress: true, 
            maxProgress: 100, 
            progress: currentProgress, 
            indeterminate: false,
            autoCancel: false,
            onlyAlertOnce: true,
          ),
        ),
      );
    }

    // Update UI-specific fields in the model before sending
    state.targetDepartureTime = targetStr;
    state.countdownText = countdownText;

    // Send current state to the UI
    service.invoke('updateUI', state.toMap());

    // --- URGENCY AND NAG LOGIC ---
    if (isPastDeadline && !state.isHome) {
      if (!state.isSnoozed) {
        if (!isUrgentShowing || minuteCounter % 4 == 0) { 
          await _sendUrgencyAlert();
          isUrgentShowing = true; 
        }

        // THE SILENT BUZZER
        final Int64List vibrationPattern = Int64List.fromList([0, 500, 100, 500, 100, 1000]);
        await flp.show(
          id: NotificationConstants.urgentId + 1, title:null, body:null,
          notificationDetails: NotificationDetails(android: AndroidNotificationDetails(
              NotificationConstants.urgentChannelId, NotificationConstants.urgentChannelName,
              importance: Importance.low, priority: Priority.low,
              vibrationPattern: vibrationPattern, enableVibration: true, onlyAlertOnce: false, 
          )),
        );
      } else {
        isUrgentShowing = false; 
      }
    } else if (isPastDeadline && state.isHome) {
      service.invoke('mission_accomplished');
        service.stopSelf();
        timer.cancel();
        positionStream?.cancel();
    }
    
    // --- HYDRATION ---
    if (!isPastDeadline && (minuteCounter % 240 == 0)) {
       await _sendHydrationAlert("Tactical water break. 💧");
    }
  });
}

// Updated Alert (No distance required)
Future<void> _sendUrgencyAlert() async {
  final FlutterLocalNotificationsPlugin flip = FlutterLocalNotificationsPlugin();
  
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.urgentChannelId, 
    NotificationConstants.urgentChannelName,
    importance: Importance.max, 
    priority: Priority.high,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    audioAttributesUsage: AudioAttributesUsage.alarm, 
    category: AndroidNotificationCategory.alarm,
    // --- FIX 3: FORCE EXPANDED VIEW TO SHOW BUTTONS ---
    styleInformation: BigTextStyleInformation(
      "Departure time exceeded. Stand down or Move out.",
      htmlFormatBigText: true,
      contentTitle: "<b>MISSION CRITICAL</b>",
      htmlFormatContentTitle: true,
    ),
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'snooze_guilt', 
        'SNOOZE (5M)', 
        cancelNotification: true, 
      ),
    ],
  );
  
  await flip.show(
    id: NotificationConstants.urgentId, 
    title: "MISSION CRITICAL: Time to Move.", 
    body: "Departure time exceeded.", 
    notificationDetails: NotificationDetails(android: ad)
  );
}

// ... rest of your helper methods (_sendGuiltNotification, _sendHydrationAlert, _sendArrivalNotification) stay the same ...

Future<void> _sendGuiltNotification(String reason) async {
  final FlutterLocalNotificationsPlugin flip = FlutterLocalNotificationsPlugin();
  AndroidNotificationDetails ad = AndroidNotificationDetails(
    NotificationConstants.guiltChannelId, NotificationConstants.guiltChannelName,
    importance: Importance.max, priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      "Snoozed for 5 mins. But remember: <b>'$reason'</b>.",
      htmlFormatBigText: true, contentTitle: "<b>Are you sure?</b>", htmlFormatContentTitle: true,
    ),
  );
  await flip.show(
    id: NotificationConstants.guiltId, 
    title: "Are you sure?", 
    body: "Remember: $reason", 
    notificationDetails: NotificationDetails(android: ad));
}

Future<void> _sendHydrationAlert(String message) async {
  final FlutterLocalNotificationsPlugin flip = FlutterLocalNotificationsPlugin();
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, NotificationConstants.hydrationChannelName,
    importance: Importance.high, priority: Priority.high, color: Color(0xFF0000FF), 
  );
  await flip.show(id: NotificationConstants.hydrationId, title: "Hydration Break", body: message, notificationDetails: NotificationDetails(android: ad));
}

Future<void> _sendArrivalNotification(String landingMsg) async {
  final FlutterLocalNotificationsPlugin flip = FlutterLocalNotificationsPlugin();
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.arrivalChannelId, NotificationConstants.arrivalChannelName,
    importance: Importance.max, priority: Priority.high,
  );
  await flip.show(id: NotificationConstants.arrivalId, title: "Safe Arrival", body: landingMsg, notificationDetails: NotificationDetails(android: ad));
}