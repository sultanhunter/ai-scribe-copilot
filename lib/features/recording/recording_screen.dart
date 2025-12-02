import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/audio_chunk.dart';
import '../../models/recording_session.dart';
import '../../providers/patient_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/app_providers.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  RecordingSession? _session;
  bool _isRecording = false;
  bool _isPaused = false;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;
  double _currentAmplitude = 0.0;
  final List<AudioChunk> _pendingChunks = [];
  int _uploadedChunks = 0;
  StreamSubscription? _amplitudeSubscription;
  StreamSubscription? _chunkSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    final audioService = ref.read(audioRecordingServiceProvider);

    _amplitudeSubscription = audioService.amplitudeStream.listen((amplitude) {
      if (mounted) {
        setState(() {
          _currentAmplitude = amplitude;
        });
      }
    });

    _chunkSubscription = audioService.chunkStream.listen((chunk) {
      if (mounted) {
        setState(() {
          _pendingChunks.add(chunk);
        });
        _uploadChunk(chunk);
      }
    });
  }

  Future<void> _uploadChunk(AudioChunk chunk) async {
    try {
      final apiService = ref.read(apiServiceProvider);

      // Get presigned URL
      await apiService.getPresignedUrl(
        sessionId: chunk.sessionId,
        chunkId: chunk.chunkId,
        sequenceNumber: chunk.sequenceNumber,
      );

      // TODO: Read chunk file and upload
      // final file = File(chunk.localPath);
      // final fileBytes = await file.readAsBytes();
      // await apiService.uploadChunk(presignedUrl, fileBytes);

      // Notify backend
      await apiService.notifyChunkUploaded(
        sessionId: chunk.sessionId,
        chunkId: chunk.chunkId,
        sequenceNumber: chunk.sequenceNumber,
      );

      if (mounted) {
        setState(() {
          _uploadedChunks++;
          _pendingChunks.remove(chunk);
        });
      }
    } catch (e) {
      debugPrint('Error uploading chunk: $e');
      // In a real app, we would retry or store for later
    }
  }

  Future<void> _startRecording() async {
    final patient = ref.read(selectedPatientProvider);
    if (patient == null) return;

    try {
      final audioService = ref.read(audioRecordingServiceProvider);
      final apiService = ref.read(apiServiceProvider);
      final userId = await ref.read(userIdProvider.future);

      // Check permissions
      if (!await audioService.checkPermissions()) {
        final granted = await audioService.requestPermissions();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).translate('permissionDenied'),
                ),
              ),
            );
          }
          return;
        }
      }

      // Create session
      final sessionData = await apiService.createSession(
        patientId: patient.id,
        userId: userId,
      );

      final sessionId = sessionData['sessionId'] as String;

      setState(() {
        _session = RecordingSession(
          sessionId: sessionId,
          patientId: patient.id,
          userId: userId,
          startTime: DateTime.now(),
          status: 'recording',
        );
        _isRecording = true;
        _isPaused = false;
        _recordingDuration = Duration.zero;
      });

      // Start recording
      await audioService.startRecording(sessionId);

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_isPaused) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate('networkError'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pauseRecording() async {
    final audioService = ref.read(audioRecordingServiceProvider);
    await audioService.pauseRecording();
    setState(() {
      _isPaused = true;
    });
  }

  Future<void> _resumeRecording() async {
    final audioService = ref.read(audioRecordingServiceProvider);
    await audioService.resumeRecording();
    setState(() {
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    final audioService = ref.read(audioRecordingServiceProvider);
    await audioService.stopRecording();

    _durationTimer?.cancel();

    setState(() {
      _isRecording = false;
      _isPaused = false;
      if (_session != null) {
        _session = _session!.copyWith(
          endTime: DateTime.now(),
          status: 'completed',
          totalChunks: _uploadedChunks + _pendingChunks.length,
          uploadedChunks: _uploadedChunks,
        );
      }
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _chunkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final patient = ref.watch(selectedPatientProvider);

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.translate('recording'))),
        body: Center(child: Text(loc.translate('selectPatient'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(patient.name)),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Audio level visualization
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording && !_isPaused
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      border: Border.all(
                        color: _isRecording && !_isPaused
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRecording && !_isPaused
                                ? Icons.mic
                                : Icons.mic_off,
                            size: 64,
                            color: _isRecording && !_isPaused
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _formatDuration(_recordingDuration),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isRecording) ...[
                    // Audio level indicator
                    Container(
                      width: 200,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _currentAmplitude.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${loc.translate('uploadedChunks')}: $_uploadedChunks',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      '${loc.translate('chunksFailed')}: ${_pendingChunks.length}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Control buttons
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isRecording)
                  ElevatedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: Text(loc.translate('startRecording')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  )
                else ...[
                  if (!_isPaused)
                    IconButton.filled(
                      onPressed: _pauseRecording,
                      icon: const Icon(Icons.pause),
                      iconSize: 32,
                    )
                  else
                    IconButton.filled(
                      onPressed: _resumeRecording,
                      icon: const Icon(Icons.play_arrow),
                      iconSize: 32,
                    ),
                  const SizedBox(width: 24),
                  IconButton.filled(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    iconSize: 32,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
