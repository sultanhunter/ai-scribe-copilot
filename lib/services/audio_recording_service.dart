import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_chunk.dart';

class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final Logger _logger = Logger();
  final _uuid = const Uuid();

  Timer? _chunkTimer;
  String? _currentSessionId;
  int _sequenceNumber = 0;
  String? _recordingPath;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<AudioChunk> _chunkController =
      StreamController<AudioChunk>.broadcast();

  Stream<double> get amplitudeStream => _amplitudeController.stream;
  Stream<AudioChunk> get chunkStream => _chunkController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> checkPermissions() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<void> startRecording(String sessionId) async {
    try {
      if (!await checkPermissions()) {
        throw Exception('Microphone permission not granted');
      }

      _currentSessionId = sessionId;
      _sequenceNumber = 0;

      // Get app directory for storing chunks
      final appDir = await getApplicationDocumentsDirectory();
      _recordingPath = '${appDir.path}/recordings/$sessionId';
      await Directory(_recordingPath!).create(recursive: true);

      // Start recording
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: AppConstants.audioSampleRate,
          bitRate: AppConstants.audioBitRate,
        ),
        path: '$_recordingPath/chunk_0.wav',
      );

      _isRecording = true;
      _startChunkTimer();
      _startAmplitudeMonitoring();

      _logger.i('Recording started for session: $sessionId');
    } catch (e) {
      _logger.e('Error starting recording: $e');
      rethrow;
    }
  }

  void _startChunkTimer() {
    _chunkTimer?.cancel();
    _chunkTimer = Timer.periodic(
      Duration(seconds: AppConstants.audioChunkDurationSeconds),
      (_) => _createChunk(),
    );
  }

  void _startAmplitudeMonitoring() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      final amplitude = await _recorder.getAmplitude();
      _amplitudeController.add(amplitude.current);
    });
  }

  Future<void> _createChunk() async {
    try {
      if (!_isRecording || _currentSessionId == null) return;

      // Stop current recording
      final currentPath = await _recorder.stop();

      if (currentPath != null) {
        final file = File(currentPath);
        if (await file.exists()) {
          final fileSize = await file.length();

          // Create chunk metadata
          final chunk = AudioChunk(
            chunkId: _uuid.v4(),
            sessionId: _currentSessionId!,
            sequenceNumber: _sequenceNumber,
            localPath: currentPath,
            fileSize: fileSize,
          );

          _chunkController.add(chunk);
          _logger.i(
            'Chunk created: ${chunk.chunkId}, sequence: $_sequenceNumber',
          );
        }
      }

      // Start recording next chunk
      _sequenceNumber++;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: AppConstants.audioSampleRate,
          bitRate: AppConstants.audioBitRate,
        ),
        path: '$_recordingPath/chunk_$_sequenceNumber.wav',
      );
    } catch (e) {
      _logger.e('Error creating chunk: $e');
    }
  }

  Future<void> pauseRecording() async {
    try {
      if (_isRecording) {
        await _recorder.pause();
        _chunkTimer?.cancel();
        _isRecording = false;
        _logger.i('Recording paused');
      }
    } catch (e) {
      _logger.e('Error pausing recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    try {
      if (!_isRecording) {
        await _recorder.resume();
        _isRecording = true;
        _startChunkTimer();
        _logger.i('Recording resumed');
      }
    } catch (e) {
      _logger.e('Error resuming recording: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      _chunkTimer?.cancel();
      _isRecording = false;

      // Create final chunk
      final finalPath = await _recorder.stop();

      if (finalPath != null && _currentSessionId != null) {
        final file = File(finalPath);
        if (await file.exists()) {
          final fileSize = await file.length();

          final chunk = AudioChunk(
            chunkId: _uuid.v4(),
            sessionId: _currentSessionId!,
            sequenceNumber: _sequenceNumber,
            localPath: finalPath,
            fileSize: fileSize,
          );

          _chunkController.add(chunk);
          _logger.i('Final chunk created: ${chunk.chunkId}');
        }
      }

      _currentSessionId = null;
      _sequenceNumber = 0;
      _recordingPath = null;

      _logger.i('Recording stopped');
    } catch (e) {
      _logger.e('Error stopping recording: $e');
      rethrow;
    }
  }

  void dispose() {
    _chunkTimer?.cancel();
    _amplitudeController.close();
    _chunkController.close();
    _recorder.dispose();
  }
}
