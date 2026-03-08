// This file defines the GuardianState class, which encapsulates the current state of the user's journey in the Guardian app. It includes information about the start time, target departure time, distance from home, and other relevant details. The class also provides methods for calculating progress and formatting distance and countdown text for display purposes.
class GuardianState {
  final DateTime startTime; // When the user hit "Start"
  final DateTime targetTime; // The deadline
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
  double distanceInMeters; 
  int polledCount;
  bool isHome;

  GuardianState({
    required this.startTime,
    required this.targetTime,
    required this.homeLat,
    required this.homeLng,
    required this.anchorReason,
    required this.homeReminderText,
    this.distanceInMeters = 0.0,
    this.polledCount = 0,
    this.isHome = false,
    this.isSnoozed = false,
    this.snoozeCount = 0,
    this.lastSnoozeTime,
    this.lastUrgentAlertTime,
    this.lastNudgeAlertTime,
    this.halfwayAlertSent = false,
    this.almostTimeAlertSent = false,
  });

  // --- GETTERS ---

  String get distanceText {
    double miles = distanceInMeters / 1609.34;
    if (miles >= 0.1) return "${miles.toStringAsFixed(1)} miles";
    return "${(distanceInMeters * 1.09361).toStringAsFixed(0)} yards";
  }

  String get countdownText {
    final diff = targetTime.difference(DateTime.now());
    if (diff.isNegative) return "LATE";
    return "${diff.inHours}h ${diff.inMinutes % 60}m";
  }

  /// Calculates progress from 0.0 to 1.0 based on time elapsed
  double get progressFactor {
    final now = DateTime.now();
    
    // Total duration of the mission
    final totalWindow = targetTime.difference(startTime).inSeconds;
    
    // How much time has passed since we started
    final elapsed = now.difference(startTime).inSeconds;

    if (totalWindow <= 0) return 1.0; // Avoid division by zero
    
    // Return a value between 0.0 and 1.0
    return (elapsed / totalWindow).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() => {
    'startTime': startTime.toIso8601String(),
    'targetTime': targetTime.toIso8601String(),
    'homeLat': homeLat,
    'homeLng': homeLng,
    'anchorReason': anchorReason,
    'homeReminderText': homeReminderText,
    'isSnoozed': isSnoozed,
    'distanceInMeters': distanceInMeters,
    'polledCount': polledCount,
    'isHome': isHome,
  };

  factory GuardianState.fromMap(Map<String, dynamic> map) {
    return GuardianState(
      startTime: DateTime.parse(map['startTime']),
      targetTime: DateTime.parse(map['targetTime']),
      homeLat: (map['homeLat'] as num).toDouble(),
      homeLng: (map['homeLng'] as num).toDouble(),
      anchorReason: map['anchorReason'] as String,
      homeReminderText: map['homeReminderText'] as String,
      isSnoozed: map['isSnoozed'] as bool? ?? false,
      distanceInMeters: (map['distanceInMeters'] as num?)?.toDouble() ?? 0.0,
      polledCount: map['polledCount'] as int? ?? 0,
      isHome: map['isHome'] as bool? ?? false,
    );
  }
}