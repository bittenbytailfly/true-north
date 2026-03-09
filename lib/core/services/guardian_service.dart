import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:true_north/core/constants.dart';
import 'package:true_north/core/models/guardian_session.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
late SharedPreferences _prefs;
late ServiceInstance _service;
late GuardianSession _session;
late StreamSubscription<Position>? positionStream;

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

// This is called by the main process, and basically just gets things ready for running
// and configures the notification channel required for persistence.
Future<void> initializeGuardianService() async {
  final service = FlutterBackgroundService();

  const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('ic_stat_app_icon');
  await _notifications.initialize(
    settings: const InitializationSettings(android: androidSettings),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    NotificationConstants.persistentChannelId,
    NotificationConstants.persistentChannelName,
    description: 'This channel is used for the persistent Guardian service.',
    importance: Importance.low,
  );

  await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

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
  DartPluginRegistrant.ensureInitialized();

  _service = service;
  _prefs = await SharedPreferences.getInstance();

  // Load the current session
  final sessionJson = _prefs.getString('guardian_session');

  if (sessionJson == null) {
    print("🚨 [CRITICAL] Guardian started with NO SESSION data. Aborting mission.");
    service.invoke('error', {'message': 'Mission parameters missing'});
    
    // Kill the service immediately so it doesn't sit there doing nothing
    service.stopSelf(); 
    return; 
  }

  // If we got here, we are safe to "Hydrate"
  try {
    _session = GuardianSession.fromMap(jsonDecode(sessionJson));
  } catch (e) {
    print("🚨 [CRITICAL] Session data corrupted: $sessionJson");
    service.stopSelf();
    return;
  }

  // Create listeners
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
  }
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // This one reports back to the UI TODO: probably should be session or perhaps both session and state
  service.on('request_state').listen((event) {
    service.invoke('updateUI', _session.toMap());
  });

  _configureLocationServices();
  _configureTimedAlerts();
}

Future<void> _configureTimedAlerts() async {

  Timer.periodic(const Duration(seconds: 15), (timer) async {
    DateTime now = DateTime.now();
    DateTime targetTime = _session.targetDepartureTime;
    bool isPastDeadline = now.isAfter(targetTime);
    
    // --- SNOOZE WAKE-UP LOGIC ---
    if (_session.isSnoozed && _session.lastSnoozeTime != null) {
      if (now.difference(_session.lastSnoozeTime!).inMinutes >= 5) {
        _session.isSnoozed = false;
        _session.lastSnoozeTime = null;

        String updatedJson = jsonEncode(_session.toMap());
        await _prefs.setString('guardian_session_key', updatedJson);
        
        print("💾 [SNOOZE] Session auto-expiry committed to disk.");
      }
    }

    await _showPersistentNotification(targetTime, now, isPastDeadline);

    if (_isUrgencyAlertDue(isPastDeadline, now)) {
      await _sendUrgencyAlert();
    }    

    if (_isNudgeMessageOverdue(isPastDeadline, now)) {
       await _sendNudgeAlert();
    }

    if (_isHalfwayThrough) {
      await _sendHalfwayNotification();
    }

    if (_isAlmostTime) {
      await _sendAlmostTimeNotification();
    }

    // Send current state to the UI
    _service.invoke('updateUI', _session.toMap());
  });
}

//#region Helpers

bool _isUrgencyAlertDue(bool isPastDeadline, DateTime now) => isPastDeadline && !_session.isSnoozed && (_session.lastUrgentAlertTime == null || now.difference(_session.lastUrgentAlertTime!).inMinutes >= 1);
bool _isNudgeMessageOverdue(bool isPastDeadline, DateTime now) => !isPastDeadline && now.difference(_session.lastNudgeAlertTime ?? _session.activationTime).inMinutes >= _session.minutesToNextNudge;
bool get _isHalfwayThrough => _session.progressFactor >= 0.5 && !_session.halfwayAlertSent;
bool get _isAlmostTime => _session.progressFactor >= 0.9 && !_session.almostTimeAlertSent;

Future<void> _updateSessionAndNotifyUI() async {
  String updatedJson = jsonEncode(_session.toMap());
  await _prefs.setString('guardian_session_key', updatedJson);
  _service.invoke('updateUI', _session.toMap());
}

//#endregion

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

Future<void> _configureLocationServices() async {
  print("🛰️ [STREAM] Initializing radar stream...");
  
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
    double distance = Geolocator.distanceBetween(position.latitude, position.longitude, _session.homeLat, _session.homeLng);

    _session.distanceInMeters = distance;

    if (_session.distanceInMeters <= 150.0) {
        print("🏁 [STREAM] Home Location Reached.");

        String landingMsg = _session.homeReminderText;
        await _sendArrivalNotification(landingMsg);
        
        _service.stopSelf(); // Kill the background service
        positionStream?.cancel(); // Kill the GPS stream

        _service.invoke('updateUI', _session.toMap());
      }
    }
  );
}

//#region Notifications

Future<void> _showPersistentNotification(DateTime targetTime, DateTime now, bool isPastDeadline) async {
  Duration diff = targetTime.difference(now);
  
  String countdownText = isPastDeadline 
      ? "LATE by ${diff.inMinutes.abs()}m" 
      : "Leave in: ${diff.inHours}h ${diff.inMinutes % 60}m (${_session.distanceText} from destination)";
  
  if (_service is AndroidServiceInstance) {
    int currentProgress = 0;
    if (!isPastDeadline) {
      DateTime activationTime = _session.activationTime;
      int totalSeconds = targetTime.difference(activationTime).inSeconds;
      int elapsedSeconds = now.difference(activationTime).inSeconds;
      if (totalSeconds > 0) currentProgress = ((elapsedSeconds / totalSeconds) * 100).toInt().clamp(0, 100);
    } else if (isPastDeadline) {
      currentProgress = 100; 
    }
  
    await _notifications.show(
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
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }
}

Future<void> _sendNudgeAlert() async {
  // 1. Pick a random message
  final random = Random();
  final String randomMessage = GuardianMessages.nudges[random.nextInt(GuardianMessages.nudges.length)];

  AndroidNotificationDetails ad = AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: const Color(0xFF4CAF50),
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Checking in ...",
    body: randomMessage, 
    notificationDetails: NotificationDetails(android: ad)
  );

  // 3. Update the last nudge time and calculate next nudge timing
  _session.lastNudgeAlertTime = DateTime.now();
  _session.minutesToNextNudge = _session.getMinutesToNextNudge();
  String updatedJson = jsonEncode(_session.toMap());
  await _prefs.setString('guardian_session_key', updatedJson);
}

Future<void> _sendHalfwayNotification() async {
  // 1. Pick a random message
  final random = Random();
  final String randomMessage = GuardianMessages.halfwayNudges[random.nextInt(GuardianMessages.halfwayNudges.length)];

  AndroidNotificationDetails ad = AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: const Color(0xFF4CAF50),
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Halfway There!",
    body: randomMessage, 
    notificationDetails: NotificationDetails(android: ad)
  );

  // 3. Update the last nudge time and calculate next nudge timing
  _session.halfwayAlertSent = true;
  _updateSessionAndNotifyUI();
}

Future<void> _sendAlmostTimeNotification() async {
  // 1. Pick a random message
  final random = Random();
  final String randomMessage = GuardianMessages.almostTimeNudges[random.nextInt(GuardianMessages.almostTimeNudges.length)];

  AndroidNotificationDetails ad = AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: const Color(0xFF4CAF50),
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Almost Time to Leave ...",
    body: randomMessage, 
    notificationDetails: NotificationDetails(android: ad)
  );

  // 3. Update the last nudge time and calculate next nudge timing
  _session.halfwayAlertSent = true;
  _updateSessionAndNotifyUI();
}

Future<void> _sendUrgencyAlert() async {
  final Int64List vibrationPattern = Int64List.fromList([0, 500, 100, 500, 100, 1000]);
  
  AndroidNotificationDetails ad = AndroidNotificationDetails(
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
    vibrationPattern: vibrationPattern,
    enableVibration: true,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'snooze_guilt', 
        'SNOOZE (5M)', 
        cancelNotification: true, 
      ),
    ],
  );
  
  await _notifications.show(
    id: NotificationConstants.urgentId, 
    title: "MISSION CRITICAL: Time to Move.", 
    body: "Departure time exceeded.", 
    notificationDetails: NotificationDetails(android: ad)
  );

  _session.lastUrgentAlertTime = DateTime.now();
  _updateSessionAndNotifyUI();
}

Future<void> _sendArrivalNotification(String landingMsg) async {
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.arrivalChannelId, NotificationConstants.arrivalChannelName,
    importance: Importance.max, priority: Priority.high,
  );
  await _notifications.show(id: NotificationConstants.arrivalId, title: "Safe Arrival", body: landingMsg, notificationDetails: NotificationDetails(android: ad));
}

//#endregion