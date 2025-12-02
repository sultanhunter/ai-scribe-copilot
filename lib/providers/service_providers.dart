import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_recording_service.dart';
import '../services/chunk_upload_service.dart';

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

// Chunk Upload Service Provider
final chunkUploadServiceProvider = Provider<ChunkUploadService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final service = ChunkUploadService(apiService);
  ref.onDispose(() => service.dispose());
  return service;
});
