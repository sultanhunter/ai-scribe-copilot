import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/recording_session.dart';
import '../services/chunk_upload_service.dart';
import 'service_providers.dart';
import 'patient_providers.dart';

final recordingSessionProvider =
    NotifierProvider<RecordingSessionNotifier, RecordingSessionState>(
      RecordingSessionNotifier.new,
    );

class RecordingSessionNotifier extends Notifier<RecordingSessionState> {
  final Logger _logger = Logger();
  StreamSubscription? _chunkSubscription;
  StreamSubscription? _amplitudeSubscription;
  StreamSubscription? _uploadProgressSubscription;
  Timer? _durationUpdateTimer;

  @override
  RecordingSessionState build() {
    return RecordingSessionState.initial();
  }

  Future<void> startRecording(String patientId, String userId) async {
    try {
      _logger.i('Starting recording for patient: $patientId');

      // Get patient name for notification
      final selectedPatient = ref.read(selectedPatientProvider);
      final patientName = selectedPatient?.name ?? 'Unknown Patient';

      // Create session on backend
      final apiService = ref.read(apiServiceProvider);
      final sessionResponse = await apiService.createSession(
        patientId: patientId,
        userId: userId,
      );

      final sessionId = sessionResponse['sessionId'] as String;
      _logger.i('Session created: $sessionId');

      final session = RecordingSession(
        sessionId: sessionId,
        patientId: patientId,
        userId: userId,
        startTime: DateTime.now(),
        status: 'recording',
      );

      state = state.copyWith(
        session: session,
        isRecording: true,
        isPaused: false,
      );

      await _startAudioRecording(sessionId, startingSequenceNumber: 0);

      // Show recording notification
      final notificationService = ref.read(
        recordingNotificationServiceProvider,
      );
      await notificationService.showRecordingNotification(
        patientName: patientName,
        duration: '00:00',
        uploadedChunks: 0,
        totalChunks: 0,
      );

      // Start timer to update notification duration every 10 seconds
      _startDurationUpdateTimer(patientName);

      _logger.i('Recording started successfully');
    } catch (e) {
      _logger.e('Error starting recording: $e');
      state = state.copyWith(error: e.toString(), isRecording: false);
      rethrow;
    }
  }

  Future<void> resumeRecordingSession() async {
    try {
      if (state.session == null) {
        throw Exception('No session to resume');
      }

      _logger.i('Resuming recording for session: ${state.session!.sessionId}');

      // Get patient name for notification
      final selectedPatient = ref.read(selectedPatientProvider);
      final patientName = selectedPatient?.name ?? 'Unknown Patient';

      state = state.copyWith(isRecording: true, isPaused: false);

      // Start from the next sequence number after the last chunk
      final startingSequence = state.session!.totalChunks;
      _logger.i('Resuming from sequence number: $startingSequence');

      await _startAudioRecording(
        state.session!.sessionId,
        startingSequenceNumber: startingSequence,
      );

      // Show recording notification
      final duration = _formatDuration(
        DateTime.now().difference(state.session!.startTime),
      );
      final notificationService = ref.read(
        recordingNotificationServiceProvider,
      );
      await notificationService.showRecordingNotification(
        patientName: patientName,
        duration: duration,
        uploadedChunks: state.uploadedChunks,
        totalChunks: state.totalChunks,
      );

      // Start timer to update notification duration every 10 seconds
      _startDurationUpdateTimer(patientName);

      _logger.i('Recording resumed successfully');
    } catch (e) {
      _logger.e('Error resuming recording: $e');
      state = state.copyWith(error: e.toString(), isRecording: false);
      rethrow;
    }
  }

  Future<void> _startAudioRecording(
    String sessionId, {
    int startingSequenceNumber = 0,
  }) async {
    // Start audio recording
    final audioService = ref.read(audioRecordingServiceProvider);
    await audioService.startRecording(
      sessionId,
      startingSequenceNumber: startingSequenceNumber,
    );

    // Listen to audio chunks and upload them
    final uploadService = ref.read(chunkUploadServiceProvider);
    _chunkSubscription = audioService.chunkStream.listen(
      (chunk) {
        _logger.i('Received chunk: ${chunk.sequenceNumber}');
        state = state.copyWith(totalChunks: state.totalChunks + 1);
        uploadService.uploadChunk(chunk);
      },
      onError: (error) {
        _logger.e('Chunk stream error: $error');
        state = state.copyWith(error: error.toString());
      },
    );

    // Listen to amplitude for visualization
    _amplitudeSubscription = audioService.amplitudeStream.listen((amplitude) {
      state = state.copyWith(currentAmplitude: amplitude);
    });

    // Listen to upload progress
    _uploadProgressSubscription = uploadService.progressStream.listen((
      progress,
    ) {
      _logger.i(
        'Upload progress - Chunk: ${progress.sequenceNumber}, '
        'Status: ${progress.status}, Queue: ${progress.queueSize}',
      );

      if (progress.status == UploadStatus.success) {
        state = state.copyWith(uploadedChunks: state.uploadedChunks + 1);
      } else if (progress.status == UploadStatus.failed) {
        state = state.copyWith(failedChunks: state.failedChunks + 1);
      }

      state = state.copyWith(
        uploadQueueSize: progress.queueSize,
        lastUploadStatus: progress.status,
      );

      // Update notification with current progress
      _updateNotification();
    });
  }

  Future<void> pauseRecording() async {
    try {
      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.pauseRecording();
      state = state.copyWith(isPaused: true);
      _logger.i('Recording paused');

      // Update notification to show paused state
      _updateNotification(isPaused: true);
    } catch (e) {
      _logger.e('Error pausing recording: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> resumeRecording() async {
    try {
      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.resumeRecording();
      state = state.copyWith(isPaused: false);
      _logger.i('Recording resumed');

      // Update notification to show resumed state
      _updateNotification();
    } catch (e) {
      _logger.e('Error resuming recording: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> stopRecording() async {
    try {
      _logger.i('Stopping recording');

      // Stop duration update timer
      _durationUpdateTimer?.cancel();
      _durationUpdateTimer = null;

      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.stopRecording();

      await _chunkSubscription?.cancel();
      await _amplitudeSubscription?.cancel();
      await _uploadProgressSubscription?.cancel();

      if (state.session != null) {
        // Update session with final chunk counts and end time
        final updatedSession = state.session!.copyWith(
          endTime: DateTime.now(),
          totalChunks: state.totalChunks,
          uploadedChunks: state.uploadedChunks,
          status: 'completed',
        );
        state = state.copyWith(
          session: updatedSession,
          isRecording: false,
          isPaused: false,
        );

        // Show completed notification
        final selectedPatient = ref.read(selectedPatientProvider);
        final patientName = selectedPatient?.name ?? 'Unknown Patient';
        final duration = _formatDuration(
          DateTime.now().difference(updatedSession.startTime),
        );
        final notificationService = ref.read(
          recordingNotificationServiceProvider,
        );

        await notificationService.showCompletedNotification(
          patientName: patientName,
          duration: duration,
          totalChunks: state.totalChunks,
        );
      }

      _logger.i('Recording stopped successfully');
    } catch (e) {
      _logger.e('Error stopping recording: $e');
      state = state.copyWith(error: e.toString(), isRecording: false);

      // Cancel notification on error
      final notificationService = ref.read(
        recordingNotificationServiceProvider,
      );
      await notificationService.cancelRecordingNotification();
    }
  }

  Future<void> waitForUploadsToComplete() async {
    _logger.i('Waiting for uploads to complete');
    final uploadService = ref.read(chunkUploadServiceProvider);

    while (uploadService.queueSize > 0) {
      await Future.delayed(const Duration(milliseconds: 500));
      _logger.i('Waiting... Queue size: ${uploadService.queueSize}');
    }

    _logger.i('All uploads completed');
  }

  Future<void> loadExistingSession(String sessionId) async {
    try {
      _logger.i('Loading existing session: $sessionId');

      final apiService = ref.read(apiServiceProvider);
      final sessionData = await apiService.getSessionDetails(sessionId);

      final session = RecordingSession(
        sessionId: sessionData['sessionId'],
        patientId: sessionData['patientId'],
        userId: sessionData['userId'],
        startTime: DateTime.parse(sessionData['startTime']),
        endTime: sessionData['endTime'] != null
            ? DateTime.parse(sessionData['endTime'])
            : null,
        status: sessionData['status'],
        totalChunks: sessionData['totalChunks'] ?? 0,
        uploadedChunks: sessionData['uploadedChunks'] ?? 0,
      );

      state = state.copyWith(
        session: session,
        isRecording: false,
        isPaused: false,
        totalChunks: session.totalChunks,
        uploadedChunks: session.uploadedChunks,
      );

      _logger.i('Session loaded successfully');
    } catch (e) {
      _logger.e('Error loading session: $e');
      state = state.copyWith(error: 'Failed to load session: $e');
    }
  }

  void reset() {
    _durationUpdateTimer?.cancel();
    _chunkSubscription?.cancel();
    _amplitudeSubscription?.cancel();
    _uploadProgressSubscription?.cancel();

    final notificationService = ref.read(recordingNotificationServiceProvider);
    notificationService.cancelRecordingNotification();

    state = RecordingSessionState.initial();
  }

  // Helper method to start timer for updating notification duration
  void _startDurationUpdateTimer(String patientName) {
    _durationUpdateTimer?.cancel();
    _durationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateNotification(),
    );
  }

  // Helper method to update notification with current recording state
  void _updateNotification({bool isPaused = false}) {
    if (state.session == null) return;

    final selectedPatient = ref.read(selectedPatientProvider);
    final patientName = selectedPatient?.name ?? 'Unknown Patient';
    final duration = _formatDuration(
      DateTime.now().difference(state.session!.startTime),
    );

    final notificationService = ref.read(recordingNotificationServiceProvider);

    notificationService.updateRecordingNotification(
      patientName: patientName,
      duration: duration,
      uploadedChunks: state.uploadedChunks,
      totalChunks: state.totalChunks,
      queueSize: state.uploadQueueSize,
      failedChunks: state.failedChunks,
    );
  }

  // Helper method to format duration as HH:MM:SS
  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class RecordingSessionState {
  final RecordingSession? session;
  final bool isRecording;
  final bool isPaused;
  final int totalChunks;
  final int uploadedChunks;
  final int failedChunks;
  final int uploadQueueSize;
  final double currentAmplitude;
  final UploadStatus? lastUploadStatus;
  final String? error;

  RecordingSessionState({
    this.session,
    required this.isRecording,
    required this.isPaused,
    required this.totalChunks,
    required this.uploadedChunks,
    required this.failedChunks,
    required this.uploadQueueSize,
    required this.currentAmplitude,
    this.lastUploadStatus,
    this.error,
  });

  factory RecordingSessionState.initial() {
    return RecordingSessionState(
      session: null,
      isRecording: false,
      isPaused: false,
      totalChunks: 0,
      uploadedChunks: 0,
      failedChunks: 0,
      uploadQueueSize: 0,
      currentAmplitude: 0.0,
      lastUploadStatus: null,
      error: null,
    );
  }

  RecordingSessionState copyWith({
    RecordingSession? session,
    bool? isRecording,
    bool? isPaused,
    int? totalChunks,
    int? uploadedChunks,
    int? failedChunks,
    int? uploadQueueSize,
    double? currentAmplitude,
    UploadStatus? lastUploadStatus,
    String? error,
  }) {
    return RecordingSessionState(
      session: session ?? this.session,
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      totalChunks: totalChunks ?? this.totalChunks,
      uploadedChunks: uploadedChunks ?? this.uploadedChunks,
      failedChunks: failedChunks ?? this.failedChunks,
      uploadQueueSize: uploadQueueSize ?? this.uploadQueueSize,
      currentAmplitude: currentAmplitude ?? this.currentAmplitude,
      lastUploadStatus: lastUploadStatus ?? this.lastUploadStatus,
      error: error ?? this.error,
    );
  }

  Duration get duration {
    if (session == null) return Duration.zero;
    final end = session!.endTime ?? DateTime.now();
    return end.difference(session!.startTime);
  }
}
