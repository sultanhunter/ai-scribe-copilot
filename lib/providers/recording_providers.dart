import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/recording_session.dart';
import '../services/chunk_upload_service.dart';
import 'service_providers.dart';
import 'patient_providers.dart';
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
        currentDuration: Duration.zero,
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
      final duration = _formatDuration(state.currentDuration);
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
    // Start continuous audio recording
    final audioService = ref.read(audioRecordingServiceProvider);
    await audioService.startRecording(sessionId);

    // Get the recording file path
    final recordingPath = audioService.recordingFilePath;
    if (recordingPath == null) {
      throw Exception('Failed to start recording - no file path');
    }

    // Start chunking service
    final chunkingService = ref.read(audioChunkingServiceProvider);
    await chunkingService.startChunking(
      sessionId: sessionId,
      recordingFilePath: recordingPath,
      startingSequenceNumber: startingSequenceNumber,
    );

    // Listen to chunks from chunking service and upload them
    final uploadService = ref.read(chunkUploadServiceProvider);
    _chunkSubscription = chunkingService.chunkStream.listen(
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

      // Get accurate counts from storage service
      final storageService = ref.read(chunkStorageServiceProvider);
      final stats = storageService.getStorageStats(sessionId: sessionId);

      // Calculate uploaded chunks (uploaded + verified)
      final uploadedCount =
          (stats['uploaded'] as int) + (stats['verified'] as int);
      final failedCount = stats['failed'] as int;

      state = state.copyWith(
        uploadedChunks: uploadedCount,
        failedChunks: failedCount,
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

      // Calculate final duration
      Duration finalDuration = state.currentDuration;

      // Stop chunking service first (will process remaining audio)
      final chunkingService = ref.read(audioChunkingServiceProvider);
      await chunkingService.stopChunking();

      // Then stop audio recording
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
          currentDuration: finalDuration,
        );

        // Show completed notification
        final selectedPatient = ref.read(selectedPatientProvider);
        final patientName = selectedPatient?.name ?? 'Unknown Patient';
        final duration = _formatDuration(finalDuration);
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

      // Calculate recorded duration from chunks
      final storageService = ref.read(chunkStorageServiceProvider);
      final chunks = storageService.getChunksBySession(sessionId);
      _logger.i('Found ${chunks.length} chunks for session $sessionId');

      final recordedDuration = chunks.fold<Duration>(
        Duration.zero,
        (total, chunk) => total + (chunk.duration ?? Duration.zero),
      );
      _logger.i('Calculated duration: $recordedDuration');
      state = state.copyWith(
        session: session,
        isRecording: false,
        isPaused: false,
        totalChunks: session.totalChunks,
        uploadedChunks: session.uploadedChunks,
        currentDuration: recordedDuration,
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
    _logger.i('Starting duration update timer');
    _durationUpdateTimer?.cancel();
    _durationUpdateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onTimerTick(),
    );
  }

  void _onTimerTick() {
    if (state.isRecording && !state.isPaused) {
      state = state.copyWith(
        currentDuration: state.currentDuration + const Duration(seconds: 1),
      );
      _updateNotification();
    }
  }

  // Helper method to update notification with current recording state
  void _updateNotification({bool isPaused = false}) {
    if (state.session == null) return;

    final selectedPatient = ref.read(selectedPatientProvider);
    final patientName = selectedPatient?.name ?? 'Unknown Patient';

    final duration = _formatDuration(state.currentDuration);

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
  // final Duration recordedDuration; // Removed
  final Duration currentDuration;

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
    // this.recordedDuration = Duration.zero,
    this.currentDuration = Duration.zero,
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
      // recordedDuration: Duration.zero,
      currentDuration: Duration.zero,
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
    // Duration? recordedDuration,
    Duration? currentDuration,
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
      // recordedDuration: recordedDuration ?? this.recordedDuration,
      currentDuration: currentDuration ?? this.currentDuration,
    );
  }
}
