import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import 'native_audio_recorder.dart';

/// Service to handle continuous audio recording to a single file
class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final NativeAudioRecorder _nativeRecorder = NativeAudioRecorder();
  final Logger _logger = Logger();

  String? _recordingFilePath;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  Stream<double> get amplitudeStream => _amplitudeController.stream;

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

      // Use native recorder on iOS for better background support
      if (Platform.isIOS) {
        await _nativeRecorder.startRecording(
          _recordingFilePath!,
          AppConstants.audioSampleRate,
        );
      } else {
        // Start continuous recording on Android
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: AppConstants.audioSampleRate,
            bitRate: AppConstants.audioBitRate,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: _recordingFilePath!,
        );
      }

      _isRecording = true;
      _startAmplitudeMonitoring();

      _logger.i('Continuous recording started for session: $sessionId');
      _logger.i('Recording to: $_recordingFilePath');
    } catch (e) {
      _logger.e('Error starting recording: $e');
      rethrow;
    }
  }

  void _startAmplitudeMonitoring() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      // Only get amplitude on Android (iOS native recorder doesn't support this)
      if (Platform.isAndroid) {
        final amplitude = await _recorder.getAmplitude();
        _amplitudeController.add(amplitude.current);
      } else {
        // Send a dummy value for iOS
        _amplitudeController.add(0.5);
      }
    });
  }

  Future<void> pauseRecording() async {
    try {
      if (_isRecording) {
        if (Platform.isIOS) {
          await _nativeRecorder.pauseRecording();
        } else {
          await _recorder.pause();
        }
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
        if (Platform.isIOS) {
          await _nativeRecorder.resumeRecording();
        } else {
          await _recorder.resume();
        }
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
      final finalPath = Platform.isIOS
          ? await _nativeRecorder.stopRecording()
          : await _recorder.stop();

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
    _amplitudeController.close();
    _recorder.dispose();
  }
}
