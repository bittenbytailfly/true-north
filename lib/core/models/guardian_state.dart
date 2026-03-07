class GuardianState {
  final DateTime startTime; // When the user hit "Start"
  final DateTime targetTime; // The deadline
  double distanceInMeters; 
  int polledCount;
  bool isHome;

  GuardianState({
    required this.startTime,
    required this.targetTime,
    this.distanceInMeters = 0.0,
    this.polledCount = 0,
    this.isHome = false,
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
    'distanceText': distanceText,
    'countdownText': countdownText,
    'distanceRaw': distanceInMeters,
    'polledCount': polledCount,
    'isHome': isHome,
    'progress': progressFactor, 
  };
}