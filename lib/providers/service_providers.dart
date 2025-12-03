import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/audio_recording_service.dart';
import '../services/audio_chunking_service.dart';
import '../services/chunk_upload_service.dart';
import '../services/chunk_storage_service.dart';
import '../services/recording_notification_service.dart';
import '../services/audio_level_service.dart';
import '../models/audio_chunk.dart';
import 'recording_providers.dart';

// Audio Level Service Provider
final audioLevelServiceProvider = Provider<AudioLevelService>((ref) {
  final service = AudioLevelService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Chunk Storage Service Provider (Singleton)
final chunkStorageServiceProvider = Provider<ChunkStorageService>((ref) {
  final service = ChunkStorageService();
  ref.onDispose(() => service.close());
  return service;
});

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

// Audio Chunking Service Provider
final audioChunkingServiceProvider = Provider<AudioChunkingService>((ref) {
  final service = AudioChunkingService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Chunk Upload Service Provider
final chunkUploadServiceProvider = Provider<ChunkUploadService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final storageService = ref.watch(chunkStorageServiceProvider);
  final service = ChunkUploadService(apiService, storageService);
  ref.onDispose(() => service.dispose());
  return service;
});

// Recording Notification Service Provider
final recordingNotificationServiceProvider =
    Provider<RecordingNotificationService>((ref) {
      final service = RecordingNotificationService();
      ref.onDispose(() => service.dispose());
      return service;
    });

// Stream provider for real-time chunk status updates
final chunksStreamProvider = StreamProvider.family<List<AudioChunk>, String?>((
  ref,
  sessionId,
) {
  final storageService = ref.watch(chunkStorageServiceProvider);
  final uploadService = ref.watch(chunkUploadServiceProvider);

  // Listen to upload progress and refresh chunk list
  return uploadService.progressStream.asyncMap((_) async {
    if (sessionId != null) {
      return storageService.getChunksBySession(sessionId);
    }
    return storageService.box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });
});

// Provider for current session chunks
final currentSessionChunksProvider = Provider<List<AudioChunk>>((ref) {
  final recordingState = ref.watch(recordingSessionProvider);
  final storageService = ref.watch(chunkStorageServiceProvider);

  if (recordingState.session?.sessionId != null) {
    return storageService.getChunksBySession(recordingState.session!.sessionId);
  }
  return [];
});
