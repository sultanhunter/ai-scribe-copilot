class AppConstants {
  // API Configuration
  static const String baseUrl =
      'YOUR_BACKEND_URL'; // Will be replaced with actual URL
  static const String apiVersion = 'v1';

  // Audio Recording Settings
  static const int audioChunkDurationSeconds = 5; // 5 second chunks
  static const int audioSampleRate = 16000;
  static const int audioBitRate = 128000;

  // Storage Keys
  static const String themeKey = 'app_theme';
  static const String localeKey = 'app_locale';
  static const String userIdKey = 'user_id';

  // Upload Settings
  static const int maxRetryAttempts = 3;
  static const int retryDelaySeconds = 2;

  // Hive Boxes
  static const String chunksBoxName = 'audio_chunks';
  static const String sessionsBoxName = 'sessions';
  static const String patientsBoxName = 'patients';
}
