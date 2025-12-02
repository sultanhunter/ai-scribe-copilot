import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../models/recording_session.dart';
import '../services/chunk_upload_service.dart';
import 'service_providers.dart';

final recordingSessionProvider =
    NotifierProvider<RecordingSessionNotifier, RecordingSessionState>(
      RecordingSessionNotifier.new,
    );

class RecordingSessionNotifier extends Notifier<RecordingSessionState> {
  final Logger _logger = Logger();
  StreamSubscription? _chunkSubscription;
  StreamSubscription? _amplitudeSubscription;
  StreamSubscription? _uploadProgressSubscription;

  @override
  RecordingSessionState build() {
    return RecordingSessionState.initial();
  }

  Future<void> startRecording(String patientId, String userId) async {
    try {
      _logger.i('Starting recording for patient: $patientId');

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

      // Start audio recording
      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.startRecording(sessionId);

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
      });

      _logger.i('Recording started successfully');
    } catch (e) {
      _logger.e('Error starting recording: $e');
      state = state.copyWith(error: e.toString(), isRecording: false);
      rethrow;
    }
  }

  Future<void> pauseRecording() async {
    try {
      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.pauseRecording();
      state = state.copyWith(isPaused: true);
      _logger.i('Recording paused');
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
    } catch (e) {
      _logger.e('Error resuming recording: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> stopRecording() async {
    try {
      _logger.i('Stopping recording');

      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.stopRecording();

      await _chunkSubscription?.cancel();
      await _amplitudeSubscription?.cancel();
      await _uploadProgressSubscription?.cancel();

      if (state.session != null) {
        final updatedSession = state.session!.copyWith(endTime: DateTime.now());
        state = state.copyWith(
          session: updatedSession,
          isRecording: false,
          isPaused: false,
        );
      }

      _logger.i('Recording stopped successfully');
    } catch (e) {
      _logger.e('Error stopping recording: $e');
      state = state.copyWith(error: e.toString(), isRecording: false);
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

  void reset() {
    _chunkSubscription?.cancel();
    _amplitudeSubscription?.cancel();
    _uploadProgressSubscription?.cancel();
    state = RecordingSessionState.initial();
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
