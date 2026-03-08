// This file defines the GuardianSession class, which encapsulates all the relevant information about a user's session in the Guardian app. It includes details about the target departure time, activation time, home location, and various alert states. The class also provides methods for converting to and from a map representation, which is useful for storing and retrieving session data from persistent storage.
import 'dart:math';

class GuardianSession {
  final DateTime targetDepartureTime; 
  final DateTime activationTime; 
  final double homeLat;
  final double homeLng;
  final String anchorReason;
  final String homeReminderText;
  bool isSnoozed;
  int snoozeCount;
  DateTime? lastSnoozeTime;
  DateTime? lastUrgentAlertTime;
  DateTime? lastNudgeAlertTime;
  bool halfwayAlertSent;
  bool almostTimeAlertSent;
  int minutesToNextNudge;
  double distanceInMeters; 

  GuardianSession({
    required this.targetDepartureTime,
    required this.activationTime,
    required this.homeLat,
    required this.homeLng,
    required this.anchorReason,
    required this.homeReminderText,
    this.isSnoozed = false,
    this.snoozeCount = 0,
    this.lastSnoozeTime,
    this.lastUrgentAlertTime,
    this.lastNudgeAlertTime,
    this.halfwayAlertSent = false,
    this.almostTimeAlertSent = false,
    this.minutesToNextNudge = 30,
    this.distanceInMeters = 0.0,
  }){
    minutesToNextNudge = getMinutesToNextNudge();
  }

  String get distanceText {
    double miles = distanceInMeters / 1609.34;
    if (miles >= 0.1) return "${miles.toStringAsFixed(1)} miles";
    return "${(distanceInMeters * 1.09361).toStringAsFixed(0)} yards";
  }

  String get countdownText {
    final diff = targetDepartureTime.difference(DateTime.now());
    if (diff.isNegative) return "LATE";
    return "${diff.inHours}h ${diff.inMinutes % 60}m";
  }

  /// Calculates progress from 0.0 to 1.0 based on time elapsed
  double get progressFactor {
    final now = DateTime.now();
    
    // Total duration of the mission
    final totalWindow = targetDepartureTime.difference(activationTime).inSeconds;
    
    // How much time has passed since we started
    final elapsed = now.difference(activationTime).inSeconds;

    if (totalWindow <= 0) return 1.0; // Avoid division by zero
    
    // Return a value between 0.0 and 1.0
    return (elapsed / totalWindow).clamp(0.0, 1.0);
  }

  /// Randomized nudge timing between 30 and 90 minutes
  int getMinutesToNextNudge() {
    final random = Random();
    return 1;
    return random.nextInt(61) + 30;
  }

  Map<String, dynamic> toMap() => {
    'targetDepartureTime': targetDepartureTime.toIso8601String(),
    'activationTime': activationTime.toIso8601String(),
    'homeLat': homeLat,
    'homeLng': homeLng,
    'anchorReason': anchorReason,
    'homeReminderText': homeReminderText,
    'isSnoozed': isSnoozed,
    'snoozeCount': snoozeCount,
    'lastSnoozeTime': lastSnoozeTime?.toIso8601String(),
    'lastUrgentAlertTime': lastUrgentAlertTime?.toIso8601String(),
    'lastNudgeAlertTime': lastNudgeAlertTime?.toIso8601String(),
    'halfwayAlertSent': halfwayAlertSent,
    'almostTimeAlertSent': almostTimeAlertSent,
  };

  factory GuardianSession.fromMap(Map<String, dynamic> map) => GuardianSession(
    targetDepartureTime: DateTime.parse(map['targetDepartureTime']),
    activationTime: DateTime.parse(map['activationTime']),
    homeLat: map['homeLat'],
    homeLng: map['homeLng'],
    anchorReason: map['anchorReason'],
    homeReminderText: map['homeReminderText'],
    isSnoozed: map['isSnoozed'] ?? false,
    snoozeCount: map['snoozeCount'] ?? 0,
    lastSnoozeTime: map['lastSnoozeTime'] != null ? DateTime.parse(map['lastSnoozeTime']) : null,
    lastUrgentAlertTime: map['lastUrgentAlertTime'] != null ? DateTime.parse(map['lastUrgentAlertTime']) : null,
    lastNudgeAlertTime: map['lastNudgeAlertTime'] != null ? DateTime.parse(map['lastNudgeAlertTime']) : null,
    halfwayAlertSent: map['halfwayAlertSent'] ?? false,
    almostTimeAlertSent: map['almostTimeAlertSent'] ?? false,
  );
}