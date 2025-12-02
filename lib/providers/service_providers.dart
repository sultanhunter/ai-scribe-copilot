import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_recording_service.dart';

// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// Audio Recording Service Provider
final audioRecordingServiceProvider = Provider<AudioRecordingService>((ref) {
  final service = AudioRecordingService();
  ref.onDispose(() => service.dispose());
  return service;
});
