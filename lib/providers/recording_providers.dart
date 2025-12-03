import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:audio_session/audio_session.dart';
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
  StreamSubscription? _uploadProgressSubscription;
  StreamSubscription? _audioLevelSubscription;
  Timer? _durationUpdateTimer;
  bool _pausedByInterruption = false;

  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;

  @override
  RecordingSessionState build() {
    return RecordingSessionState.initial();
  }

  Future<void> _initAudioSession() async {
    _audioSession = await AudioSession.instance;
    await _audioSession!.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ),
    );
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
      );

      state = state.copyWith(
        session: session,
        isRecording: true,
        isPaused: false,
        currentDuration: Duration.zero,
      );

      await _startAudioRecording(sessionId, startingSequenceNumber: 0);

      // Start audio level monitoring
      _startAudioLevelMonitoring();

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

      // Start audio level monitoring
      _startAudioLevelMonitoring();

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
    // Initialize and activate audio session
    await _initAudioSession();
    if (await _audioSession!.setActive(true)) {
      _logger.i('Audio session activated');
    } else {
      _logger.w('Failed to activate audio session');
    }

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

    // Listen to audio interruptions (e.g. phone calls)
    _interruptionSubscription = _audioSession!.interruptionEventStream.listen((
      event,
    ) async {
      if (event.begin) {
        if (state.isRecording && !state.isPaused) {
          _logger.i('Audio interruption began, pausing recording');
          _pausedByInterruption = true;
          await pauseRecording();

          // Show interruption notification
          final selectedPatient = ref.read(selectedPatientProvider);
          final patientName = selectedPatient?.name ?? 'Unknown Patient';
          final notificationService = ref.read(
            recordingNotificationServiceProvider,
          );
          await notificationService.showInterruptionNotification(
            patientName: patientName,
          );
        }
      } else {
        if (_pausedByInterruption) {
          _logger.i('Audio interruption ended. Waiting for user to resume.');
          // Do not auto-resume. User must resume manually.
          _pausedByInterruption = false;
        }
      }
    });
  }

  Future<void> pauseRecording() async {
    try {
      final audioService = ref.read(audioRecordingServiceProvider);
      await audioService.pauseRecording();

      state = state.copyWith(isPaused: true, currentAudioLevel: 0.0);
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

      _pausedByInterruption = false;
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
      await _uploadProgressSubscription?.cancel();
      await _interruptionSubscription?.cancel();
      await _audioLevelSubscription?.cancel();

      // Deactivate session
      await _audioSession?.setActive(false);

      // Stop audio level monitoring
      await _stopAudioLevelMonitoring();

      if (state.session != null) {
        // Update session with final chunk counts and end time
        final updatedSession = state.session!.copyWith(
          totalChunks: state.totalChunks,
          uploadedChunks: state.uploadedChunks,
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
    _uploadProgressSubscription?.cancel();
    _interruptionSubscription?.cancel();
    _audioLevelSubscription?.cancel();

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

    // If paused by interruption, don't overwrite the interruption notification
    // with standard progress updates.
    if (_pausedByInterruption) return;

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

  // Start monitoring audio levels
  void _startAudioLevelMonitoring() {
    final audioLevelService = ref.read(audioLevelServiceProvider);

    audioLevelService
        .startMonitoring()
        .then((_) {
          _audioLevelSubscription = audioLevelService.levelStream.listen(
            (level) {
              if (state.isRecording && !state.isPaused) {
                state = state.copyWith(currentAudioLevel: level);
              }
            },
            onError: (error) {
              _logger.e('Audio level stream error: $error');
            },
          );
        })
        .catchError((error) {
          _logger.e('Failed to start audio level monitoring: $error');
        });
  }

  // Stop monitoring audio levels
  Future<void> _stopAudioLevelMonitoring() async {
    await _audioLevelSubscription?.cancel();
    _audioLevelSubscription = null;

    final audioLevelService = ref.read(audioLevelServiceProvider);
    await audioLevelService.stopMonitoring();
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
  final UploadStatus? lastUploadStatus;
  final String? error;
  // final Duration recordedDuration; // Removed
  final Duration currentDuration;
  final double currentAudioLevel;

  RecordingSessionState({
    this.session,
    required this.isRecording,
    required this.isPaused,
    required this.totalChunks,
    required this.uploadedChunks,
    required this.failedChunks,
    required this.uploadQueueSize,
    this.lastUploadStatus,
    this.error,
    // this.recordedDuration = Duration.zero,
    this.currentDuration = Duration.zero,
    this.currentAudioLevel = 0.0,
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
      lastUploadStatus: null,
      error: null,
      // recordedDuration: Duration.zero,
      currentDuration: Duration.zero,
      currentAudioLevel: 0.0,
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
    UploadStatus? lastUploadStatus,
    String? error,
    // Duration? recordedDuration,
    Duration? currentDuration,
    double? currentAudioLevel,
  }) {
    return RecordingSessionState(
      session: session ?? this.session,
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      totalChunks: totalChunks ?? this.totalChunks,
      uploadedChunks: uploadedChunks ?? this.uploadedChunks,
      failedChunks: failedChunks ?? this.failedChunks,
      uploadQueueSize: uploadQueueSize ?? this.uploadQueueSize,
      lastUploadStatus: lastUploadStatus ?? this.lastUploadStatus,
      error: error ?? this.error,
      // recordedDuration: recordedDuration ?? this.recordedDuration,
      currentDuration: currentDuration ?? this.currentDuration,
      currentAudioLevel: currentAudioLevel ?? this.currentAudioLevel,
    );
  }
}
