import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class NativeAudioRecorder {
  static const MethodChannel _channel = MethodChannel(
    'ai_scribe_copilot/audio_recorder',
  );
  final Logger _logger = Logger();

  /// Start recording to the specified path
  Future<bool> startRecording(String path, int sampleRate) async {
    try {
      // if (!Platform.isIOS) {
      //   throw UnsupportedError('Native recorder only supports iOS');
      // }

      final result = await _channel.invokeMethod<bool>('startRecording', {
        'path': path,
        'sampleRate': sampleRate,
      });

      _logger.i('Native recording started: $path');
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.e('Failed to start native recording: ${e.message}');
      rethrow;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    try {
      final path = await _channel.invokeMethod<String>('stopRecording');
      _logger.i('Native recording stopped: $path');
      return path;
    } on PlatformException catch (e) {
      _logger.e('Failed to stop native recording: ${e.message}');
      rethrow;
    }
  }

  /// Pause recording
  Future<bool> pauseRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('pauseRecording');
      _logger.i('Native recording paused');
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.e('Failed to pause native recording: ${e.message}');
      rethrow;
    }
  }

  /// Resume recording
  Future<bool> resumeRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('resumeRecording');
      _logger.i('Native recording resumed');
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.e('Failed to resume native recording: ${e.message}');
      rethrow;
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRecording');
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.e('Failed to check recording status: ${e.message}');
      return false;
    }
  }
}
