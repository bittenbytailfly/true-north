// This file defines the GuardianSession class, which encapsulates all the relevant information about a user's session in the Guardian app. It includes details about the target departure time, activation time, home location, and various alert states. The class also provides methods for converting to and from a map representation, which is useful for storing and retrieving session data from persistent storage.
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
  });

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