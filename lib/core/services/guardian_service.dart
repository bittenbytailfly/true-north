import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:true_north/core/constants.dart';
import 'package:true_north/core/models/guardian_session.dart';
import 'package:true_north/core/session_repository.dart';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
late ServiceInstance _service;
late GuardianSession _session;
StreamSubscription<Position>? positionStream;

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // Snooze logic removed from here—now handled entirely in the UI.
}

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

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  final repository = SessionRepository();
  final session = await repository.getSession();

  if (session == null) {
    service.invoke('error', {'message': 'Mission parameters missing'});
    service.stopSelf(); 
    return; 
  } else {
    print("✅ [SERVICE] Session loaded successfully.");
  }

  _session = session;

  service.on('stopService').listen((event) {
    positionStream?.cancel();
    service.stopSelf();
  });

  service.on('request_state').listen((event) {
    service.invoke('updateUI', _session.toMap());
  });

  // 🛡️ NEW: Listen for the snooze command from the UI
  service.on('snooze_mission').listen((event) async {
    print("💤 [SERVICE] Snooze command received from UI.");
    _session.isSnoozed = true;
    _session.lastSnoozeTime = DateTime.now();
    
    await SessionRepository().saveSession(_session);
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
        
        await SessionRepository().saveSession(_session); 
        print("💾 [SNOOZE] Session auto-expiry committed to disk.");
      }
    }

    await _showPersistentNotification(targetTime, now, isPastDeadline);

    if (_isUrgencyAlertDue(isPastDeadline, now)) await _sendUrgencyAlert();
    if (_isNudgeMessageOverdue(isPastDeadline, now)) await _sendNudgeAlert();
    if (_isHalfwayThrough) await _sendHalfwayNotification();
    if (_isAlmostTime) await _sendAlmostTimeNotification();

    _service.invoke('updateUI', _session.toMap());
  });
}

// --- Helpers ---

bool _isUrgencyAlertDue(bool isPastDeadline, DateTime now) => isPastDeadline && !_session.isSnoozed && (_session.lastUrgentAlertTime == null || now.difference(_session.lastUrgentAlertTime!).inMinutes >= 1);
bool _isNudgeMessageOverdue(bool isPastDeadline, DateTime now) => _session.nudgesEnabled && !isPastDeadline && now.difference(_session.lastNudgeAlertTime ?? _session.activationTime).inMinutes >= _session.minutesToNextNudge; 
bool get _isHalfwayThrough => _session.progressFactor >= 0.5 && !_session.halfwayAlertSent;
bool get _isAlmostTime => _session.progressFactor >= 0.9 && !_session.almostTimeAlertSent;

Future<void> _updateSessionAndNotifyUI() async {
  await SessionRepository().saveSession(_session); 
  _service.invoke('updateUI', _session.toMap());
}

Future<void> _configureLocationServices() async {
  print("🛰️ [STREAM] Initializing radar stream...");
  
  final locationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 50, 
  );

  positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
    double distance = Geolocator.distanceBetween(position.latitude, position.longitude, _session.homeLat, _session.homeLng);
    _session.distanceInMeters = distance;

    if (distance <= 150.0) {
        print("🏁 [STREAM] Home Location Reached.");
        String landingMsg = _session.homeReminderText;
        await _sendArrivalNotification(landingMsg);
        
        _service.stopSelf(); 
        positionStream?.cancel(); 
        _service.invoke('updateUI', _session.toMap());
      }
    }
  );
}

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
  final String randomMessage = "Stay sharp. How's that water level looking? 🌊";

  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: Color(0xFF4CAF50),
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Checking in ...",
    body: randomMessage, 
    notificationDetails: NotificationDetails(android: ad)
  );

  _session.lastNudgeAlertTime = DateTime.now();
  _session.minutesToNextNudge = 15; 
  await _updateSessionAndNotifyUI();
}

Future<void> _sendHalfwayNotification() async {
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: Color(0xFF4CAF50),
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Halfway There!",
    body: "50% of the mission complete. You're pacing this perfectly. 🏆", 
    notificationDetails: NotificationDetails(android: ad)
  );

  _session.halfwayAlertSent = true;
  await _updateSessionAndNotifyUI();
}

Future<void> _sendAlmostTimeNotification() async {
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.hydrationChannelId, 
    NotificationConstants.hydrationChannelName,
    importance: Importance.high, 
    priority: Priority.high, 
    icon: 'ic_stat_app_icon',
    color: Color(0xFFE67E22), 
  );

  await _notifications.show(
    id: NotificationConstants.hydrationId, 
    title: "Almost Time to Leave ...",
    body: "T-minus 10%: Time to start the 'Exit Protocol'. 🛫", 
    notificationDetails: NotificationDetails(android: ad)
  );

  _session.almostTimeAlertSent = true; 
  await _updateSessionAndNotifyUI();
}

Future<void> _sendUrgencyAlert() async {
  final Int64List vibrationPattern = Int64List.fromList([0, 100, 100, 100, 100, 100, 100, 100, 100, 500, 100, 500, 100, 500]); // Vibrate for 100ms, pause for 100ms, repeated 5 times
  
  // 🛡️ REFACTOR: Removed fullScreenIntent and actions
  AndroidNotificationDetails ad = AndroidNotificationDetails(
    NotificationConstants.urgentChannelId, 
    NotificationConstants.urgentChannelName,
    importance: Importance.max, 
    priority: Priority.high,
    ongoing: true,
    autoCancel: false,
    audioAttributesUsage: AudioAttributesUsage.alarm, 
    category: AndroidNotificationCategory.alarm,
    styleInformation: const BigTextStyleInformation(
      "Departure time exceeded. Tap to open Guardian and stand down or snooze.",
      htmlFormatBigText: true,
      contentTitle: "<b>MISSION CRITICAL</b>",
      htmlFormatContentTitle: true,
    ),
    vibrationPattern: vibrationPattern,
    enableVibration: true,
  );
  
  await _notifications.show(
    id: NotificationConstants.urgentId, 
    title: "MISSION CRITICAL", 
    body: "Departure time exceeded. Tap to open.", 
    notificationDetails: NotificationDetails(android: ad)
  );

  _session.lastUrgentAlertTime = DateTime.now();
  await _updateSessionAndNotifyUI();
}

Future<void> _sendArrivalNotification(String landingMsg) async {
  AndroidNotificationDetails ad = const AndroidNotificationDetails(
    NotificationConstants.arrivalChannelId, NotificationConstants.arrivalChannelName,
    importance: Importance.max, priority: Priority.high,
  );
  await _notifications.show(id: NotificationConstants.arrivalId, title: "Safe Arrival", body: landingMsg, notificationDetails: NotificationDetails(android: ad));
}