import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:record/record.dart';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import 'native_audio_recorder.dart';

/// Service to handle continuous audio recording to a single file
class AudioRecordingService {
  // final AudioRecorder _recorder = AudioRecorder();
  final NativeAudioRecorder _nativeRecorder = NativeAudioRecorder();
  final Logger _logger = Logger();

  String? _recordingFilePath;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Get the current recording file path
  String? get recordingFilePath => _recordingFilePath;

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

      // Get app directory for storing recording
      final appDir = await getApplicationDocumentsDirectory();
      final recordingDir = '${appDir.path}/recordings/$sessionId';
      await Directory(recordingDir).create(recursive: true);

      // Use unique filename for each segment to avoid overwriting
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingFilePath = '$recordingDir/recording_$timestamp.wav';

      // Use native recorder on both platforms
      await _nativeRecorder.startRecording(
        _recordingFilePath!,
        AppConstants.audioSampleRate,
      );

      _isRecording = true;

      _logger.i('Continuous recording started for session: $sessionId');
      _logger.i('Recording to: $_recordingFilePath');
    } catch (e) {
      _logger.e('Error starting recording: $e');
      rethrow;
    }
  }

  Future<void> pauseRecording() async {
    try {
      if (_isRecording) {
        await _nativeRecorder.pauseRecording();
        _isRecording = false;
        _logger.i('Recording paused');
      }
    } catch (e) {
      _logger.e('Error pausing recording: $e');
      rethrow;
    }
  }

  Future<void> resumeRecording() async {
    try {
      if (!_isRecording) {
        await _nativeRecorder.resumeRecording();
        _isRecording = true;
        _logger.i('Recording resumed');
      }
    } catch (e) {
      _logger.e('Error resuming recording: $e');
      rethrow;
    }
  }

  Future<String?> stopRecording() async {
    try {
      _isRecording = false;

      // Stop recording and get final file path
      final finalPath = await _nativeRecorder.stopRecording();

      _logger.i('Recording stopped. File: $finalPath');

      if (finalPath != null) {
        final file = File(finalPath);
        if (await file.exists()) {
          final fileSize = await file.length();
          _logger.i('Final recording size: $fileSize bytes');
        }
      }

      final returnPath = finalPath;
      _recordingFilePath = null;

      return returnPath;
    } catch (e) {
      _logger.e('Error stopping recording: $e');
      rethrow;
    }
  }

  void dispose() {
    // _recorder.dispose();
  }
}
