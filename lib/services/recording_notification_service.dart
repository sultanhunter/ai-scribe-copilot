import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

class RecordingNotificationService {
  static const int recordingNotificationId = 1;
  static const String channelId = 'recording_channel';
  static const String channelName = 'Recording Notifications';
  static const String channelDescription =
      'Shows recording status and progress';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();

  Future<void> initialize() async {
    if (!Platform.isIOS) return;

    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      iOS: initializationSettingsIOS,
    );

    await _notifications.initialize(initializationSettings);
    _logger.i('Recording notification service initialized');
  }

  Future<void> requestPermissions() async {
    if (!Platform.isIOS) return;

    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: false);
  }

  Future<void> showRecordingNotification({
    required String patientName,
    required String duration,
    required int uploadedChunks,
    required int totalChunks,
  }) async {
    if (!Platform.isIOS) return;

    try {
      const notificationDetails = NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
          // Keep notification visible even when app is in foreground
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

      await _notifications.show(
        recordingNotificationId,
        '🎙️ Recording - $patientName',
        '$duration • Uploaded: $uploadedChunks/$totalChunks chunks',
        notificationDetails,
      );
    } catch (e) {
      _logger.e('Error showing recording notification: $e');
    }
  }

  Future<void> updateRecordingNotification({
    required String patientName,
    required String duration,
    required int uploadedChunks,
    required int totalChunks,
    int? queueSize,
    int? failedChunks,
  }) async {
    if (!Platform.isIOS) return;

    try {
      final status = queueSize != null && queueSize > 0
          ? 'Uploading ($queueSize in queue)'
          : failedChunks != null && failedChunks > 0
          ? '⚠️ $failedChunks failed'
          : 'All uploaded';

      const notificationDetails = NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

      await _notifications.show(
        recordingNotificationId,
        '🎙️ Recording - $patientName',
        '$duration • $uploadedChunks/$totalChunks chunks • $status',
        notificationDetails,
      );
    } catch (e) {
      _logger.e('Error updating recording notification: $e');
    }
  }

  Future<void> showCompletedNotification({
    required String patientName,
    required String duration,
    required int totalChunks,
  }) async {
    if (!Platform.isIOS) return;

    try {
      const notificationDetails = NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      );

      await _notifications.show(
        recordingNotificationId,
        '✅ Recording Complete - $patientName',
        '$duration • $totalChunks chunks saved',
        notificationDetails,
      );

      // Auto-dismiss after 5 seconds
      await Future.delayed(const Duration(seconds: 5));
      await cancelRecordingNotification();
    } catch (e) {
      _logger.e('Error showing completed notification: $e');
    }
  }

  Future<void> cancelRecordingNotification() async {
    if (!Platform.isIOS) return;

    try {
      await _notifications.cancel(recordingNotificationId);
      _logger.i('Recording notification cancelled');
    } catch (e) {
      _logger.e('Error cancelling notification: $e');
    }
  }

  void dispose() {
    // Clean up if needed
  }
}
