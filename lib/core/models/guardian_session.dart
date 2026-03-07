class GuardianSession {
  bool isSnoozed;
  int snoozeCount;
  DateTime? lastSnoozeTime;
  bool halfwayAlertSent;
  bool almostTimeAlertSent;

  GuardianSession({
    this.isSnoozed = false,
    this.snoozeCount = 0,
    this.lastSnoozeTime,
    this.halfwayAlertSent = false,
    this.almostTimeAlertSent = false,
  });

  Map<String, dynamic> toMap() => {
    'isSnoozed': isSnoozed,
    'snoozeCount': snoozeCount,
    'lastSnoozeTime': lastSnoozeTime?.toIso8601String(),
    'halfwayAlertSent': halfwayAlertSent,
    'almostTimeAlertSent': almostTimeAlertSent,
  };

  factory GuardianSession.fromMap(Map<String, dynamic> map) => GuardianSession(
    isSnoozed: map['isSnoozed'] ?? false,
    snoozeCount: map['snoozeCount'] ?? 0,
    lastSnoozeTime: map['lastSnoozeTime'] != null ? DateTime.parse(map['lastSnoozeTime']) : null,
    halfwayAlertSent: map['halfwayAlertSent'] ?? false,
    almostTimeAlertSent: map['almostTimeAlertSent'] ?? false,
  );
}