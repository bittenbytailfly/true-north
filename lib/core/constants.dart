class NotificationConstants {
  // Channel IDs
  static const String urgentChannelId = 'guardian_urgent';
  static const String guiltChannelId = 'guardian_guilt';
  static const String hydrationChannelId = 'guardian_hydration';
  static const String arrivalChannelId = 'guardian_arrival';
  static const String persistentChannelId = 'guardian_channel';

  // Channel Names
  static const String urgentChannelName = 'True North Urgent';
  static const String guiltChannelName = 'True North Anchor';
  static const String hydrationChannelName = 'True North Hydration';
  static const String arrivalChannelName = 'True North Success';
  static const String persistentChannelName = 'True North Guardian';

  // Notification Unique IDs
  static const int urgentId = 777;
  static const int guiltId = 555;
  static const int hydrationId = 666;
  static const int arrivalId = 999;
  static const int persistentServiceId = 888;

  // Notification Content
  static const String guardianGpsNotificationText = "Guardian GPS Active";
  static const String guardianGpsNotificationTitle = "True North";
}

class LocationConstants {
  // Thresholds
  static const double homeDistanceThreshold = 150.0;
  static const int locationUpdateThreshold = 50; // Minimum distance change to trigger update
}

class GuardianMessages {
  static const List<String> nudges = [
    "Remember to take it slow - it's not a race! 🐢",
    "Consider switching to a non-alcoholic drink next round. 💧",
    "Tactical water break? Your future self will thank you.",
    "The Guardian says: Check your pace. You're doing great.",
    "Stay sharp. How's that water level looking? 🌊",
    "Pacing is power. Take a breather.",
    "Halfway through a drink? Grab a glass of water now.",
    "Eyes on the prize: A clear head tomorrow morning. ☀️",
    "Don't let the momentum run away with you. Slow it down.",
    "Checking in: Are you sticking to the plan? You've got this.",
  ];
  static const List<String> halfwayNudges = [
    "Halfway mark reached. The choices you make now determine how tomorrow feels.",
    "The night is at its peak. Stay sharp, stay hydrated, and stay on track. 🛡️",
    "You've handled the first half like a pro. Let's finish just as strong.",
    "Mid-mission check-in: One water now makes the second half even better. 💧",
    "The Guardian's report: Pacing is optimal. Keep the 'Home' objective in sight.",
    "Halfway there! Remember: the goal isn't just a good night, it's a great tomorrow morning. ☀️",
    "Balance check: You’ve hit the midpoint. Switch to water for a round to lock in the win.",
    "Standard halfway protocol: Assess your energy. You’re doing exactly what you planned.",
    "50% down. You're the one in control here. Keep that focus. 🎯",
  ];
  static const List<String> almostTimeNudges = [
    "T-minus 10%: Time to start the 'Exit Protocol'. You've played this perfectly. 🛫",
    "The finish line is in sight. Close out your tabs and gather your gear.",
    "90% complete. Now is the best time to say your goodbyes. Leave on a high note! 🌟",
    "Mission almost accomplished. Start the transition to 'Home' mode now.",
    "Final stretch. Check your phone, keys, and wallet. Let's make this exit smooth.",
    "The Guardian's final nudge: One last glass of water, then it's time to move out. 🛡️",
    "Don't get caught in the 'one more' trap. You're 90% through—stick to the plan!",
    "Prepare for departure. Tomorrow Morning You is already thanking Current You. ☀️",
    "Execution phase: Finish your current drink and start looking for the door. 🎯",
    "Protocol Reminder: The best part of the night is a successful return. Move out soon.",
  ];
}