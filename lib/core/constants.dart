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