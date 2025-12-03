import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Service to monitor real-time audio levels from the microphone
class AudioLevelService {
  static const MethodChannel _methodChannel = MethodChannel(
    'ai_scribe_copilot/audio_level',
  );
  static const EventChannel _eventChannel = EventChannel(
    'ai_scribe_copilot/audio_level_stream',
  );

  final Logger _logger = Logger();
  StreamSubscription? _levelSubscription;
  final _levelController = StreamController<double>.broadcast();

  /// Stream of normalized audio levels (0.0 to 1.0)
  Stream<double> get levelStream => _levelController.stream;

  /// Start monitoring audio levels
  Future<void> startMonitoring() async {
    try {
      await _methodChannel.invokeMethod('startMonitoring');
      _logger.i('Audio level monitoring started');

      // Listen to the native event stream
      _levelSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic level) {
          if (level is double) {
            // Clamp between 0.0 and 1.0
            final normalizedLevel = level.clamp(0.0, 1.0);
            _levelController.add(normalizedLevel);
          }
        },
        onError: (error) {
          _logger.e('Audio level stream error: $error');
        },
      );
    } catch (e) {
      _logger.e('Error starting audio level monitoring: $e');
      rethrow;
    }
  }

  /// Stop monitoring audio levels
  Future<void> stopMonitoring() async {
    try {
      await _levelSubscription?.cancel();
      _levelSubscription = null;
      await _methodChannel.invokeMethod('stopMonitoring');
      _logger.i('Audio level monitoring stopped');
    } catch (e) {
      _logger.e('Error stopping audio level monitoring: $e');
    }
  }

  void dispose() {
    _levelSubscription?.cancel();
    _levelController.close();
  }
}
