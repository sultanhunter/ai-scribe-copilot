class AppConstants {
  // API Configuration
  // Using local IP for physical device testing
  static const String baseUrl = 'http://192.168.1.12:3000/api';
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
