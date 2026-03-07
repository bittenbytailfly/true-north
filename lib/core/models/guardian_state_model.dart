class GuardianStateModel {
  // Core State
  int polled;
  String distance;
  bool isHome;
  bool isSnoozed;
  DateTime? snoozeStartTime;

  // UI Display Properties (Transient)
  String? targetDepartureTime;
  String countdownText;

  GuardianStateModel({
    this.polled = 0,
    this.distance = "Calculating...",
    this.isHome = false,
    this.isSnoozed = false,
    this.snoozeStartTime,
    this.targetDepartureTime,
    this.countdownText = "Loading...",
  });

  /// Serializes the model to a Map for passing over the platform channel.
  Map<String, dynamic> toMap() {
    return {
      'polled': polled,
      'distance': distance,
      'isHome': isHome,
      'isSnoozed': isSnoozed,
      'snoozeStartTime': snoozeStartTime?.millisecondsSinceEpoch,
      'targetDepartureTime': targetDepartureTime,
      'countdownText': countdownText,
    };
  }

  /// Factory to create a model from a Map (useful for the UI side).
  factory GuardianStateModel.fromMap(Map<String, dynamic> map) {
    return GuardianStateModel(
      polled: map['polled'] ?? 0,
      distance: map['distance'] ?? "Calculating...",
      isHome: map['isHome'] ?? false,
      isSnoozed: map['isSnoozed'] ?? false,
      snoozeStartTime: map['snoozeStartTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['snoozeStartTime'])
          : null,
      targetDepartureTime: map['targetDepartureTime'],
      countdownText: map['countdownText'] ?? "Loading...",
    );
  }
}