class GuardianSettings {
  final String targetDepartureTime; // ISO8601 String
  final double homeLat;
  final double homeLng;
  final String anchorReason;
  final String homeReminderText;

  GuardianSettings({
    required this.targetDepartureTime,
    required this.homeLat,
    required this.homeLng,
    required this.anchorReason,
    required this.homeReminderText,
  });

  Map<String, dynamic> toMap() => {
    'targetDepartureTime': targetDepartureTime,
    'homeLat': homeLat,
    'homeLng': homeLng,
    'anchorReason': anchorReason,
    'homeReminderText': homeReminderText,
  };

  factory GuardianSettings.fromMap(Map<String, dynamic> map) => GuardianSettings(
    targetDepartureTime: map['targetDepartureTime'],
    homeLat: map['homeLat'],
    homeLng: map['homeLng'],
    anchorReason: map['anchorReason'],
    homeReminderText: map['homeReminderText'],
  );
}