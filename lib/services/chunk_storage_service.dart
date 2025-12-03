import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:crypto/crypto.dart';
import '../models/audio_chunk.dart';

class ChunkStorageService {
  static const String _boxName = 'audio_chunks';
  final Logger _logger = Logger();
  Box<AudioChunk>? _chunksBox;

  /// Initialize Hive and open box
  Future<void> init() async {
    try {
      await Hive.initFlutter();

      // Register adapters if not already registered
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(AudioChunkAdapter());
      }
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(ChunkUploadStateAdapter());
      }

      _chunksBox = await Hive.openBox<AudioChunk>(_boxName);
      _logger.i(
        'ChunkStorageService initialized with ${_chunksBox!.length} chunks',
      );
    } catch (e) {
      _logger.e('Error initializing ChunkStorageService: $e');
      rethrow;
    }
  }

  Box<AudioChunk> get box {
    if (_chunksBox == null || !_chunksBox!.isOpen) {
      throw Exception('ChunkStorageService not initialized');
    }
    return _chunksBox!;
  }

  /// Calculate MD5 checksum for file integrity
  Future<String> calculateChecksum(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final digest = md5.convert(bytes);
      return digest.toString();
    } catch (e) {
      _logger.e('Error calculating checksum: $e');
      rethrow;
    }
  }

  /// Save chunk to persistent storage
  Future<void> saveChunk(AudioChunk chunk) async {
    try {
      // Calculate checksum if not already set
      if (chunk.checksum == null) {
        final checksum = await calculateChecksum(chunk.localPath);
        final chunkWithChecksum = chunk.copyWith(checksum: checksum);
        await box.put(chunk.chunkId, chunkWithChecksum);
        _logger.i('Saved chunk ${chunk.chunkId} with checksum');
      } else {
        await box.put(chunk.chunkId, chunk);
        _logger.i('Saved chunk ${chunk.chunkId}');
      }
    } catch (e) {
      _logger.e('Error saving chunk: $e');
      rethrow;
    }
  }

  /// Update chunk state
  Future<void> updateChunkState(
    String chunkId,
    ChunkUploadState state, {
    String? errorMessage,
  }) async {
    try {
      final chunk = box.get(chunkId);
      if (chunk != null) {
        chunk.uploadState = state;
        chunk.lastAttemptTime = DateTime.now();
        if (errorMessage != null) {
          chunk.errorMessage = errorMessage;
        }
        await chunk.save();
        _logger.i('Updated chunk $chunkId state to $state');
      }
    } catch (e) {
      _logger.e('Error updating chunk state: $e');
      rethrow;
    }
  }

  /// Increment retry count
  Future<void> incrementRetryCount(String chunkId) async {
    try {
      final chunk = box.get(chunkId);
      if (chunk != null) {
        chunk.retryCount++;
        chunk.lastAttemptTime = DateTime.now();
        await chunk.save();
        _logger.i(
          'Incremented retry count for chunk $chunkId to ${chunk.retryCount}',
        );
      }
    } catch (e) {
      _logger.e('Error incrementing retry count: $e');
      rethrow;
    }
  }

  /// Get chunks by state
  List<AudioChunk> getChunksByState(ChunkUploadState state) {
    return box.values.where((chunk) => chunk.uploadState == state).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  /// Reset retry count for a chunk (used for manual retry of failed chunks)
  Future<void> resetRetryCount(String chunkId) async {
    try {
      final chunk = box.get(chunkId);
      if (chunk != null) {
        chunk.retryCount = 0;
        chunk.errorMessage = null;
        chunk.lastAttemptTime = DateTime.now();
        await chunk.save();
        _logger.i('Reset retry count for chunk $chunkId');
      }
    } catch (e) {
      _logger.e('Error resetting retry count: $e');
      rethrow;
    }
  }

  /// Get all pending chunks (recorded or uploading, excludes failed)
  List<AudioChunk> getPendingChunks() {
    return box.values
        .where(
          (chunk) =>
              chunk.uploadState == ChunkUploadState.recorded ||
              chunk.uploadState == ChunkUploadState.uploading,
        )
        .toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  /// Get all failed chunks
  List<AudioChunk> getFailedChunks() {
    return box.values
        .where((chunk) => chunk.uploadState == ChunkUploadState.failed)
        .toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  /// Retry all failed chunks by resetting their state and retry count
  Future<int> retryAllFailedChunks() async {
    try {
      final failedChunks = getFailedChunks();
      for (final chunk in failedChunks) {
        chunk.uploadState = ChunkUploadState.recorded;
        chunk.retryCount = 0;
        chunk.errorMessage = null;
        chunk.lastAttemptTime = DateTime.now();
        await chunk.save();
      }
      _logger.i('Reset ${failedChunks.length} failed chunks for retry');
      return failedChunks.length;
    } catch (e) {
      _logger.e('Error retrying failed chunks: $e');
      rethrow;
    }
  }

  /// Get chunks by session ID
  List<AudioChunk> getChunksBySession(String sessionId) {
    return box.values.where((chunk) => chunk.sessionId == sessionId).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  /// Get chunk by ID
  AudioChunk? getChunk(String chunkId) {
    return box.get(chunkId);
  }

  /// Delete chunk and local file after verification
  Future<void> deleteChunk(String chunkId, {bool deleteFile = true}) async {
    try {
      final chunk = box.get(chunkId);
      if (chunk != null) {
        // Delete local file if requested
        if (deleteFile && chunk.localPath.isNotEmpty) {
          final file = File(chunk.localPath);
          if (await file.exists()) {
            await file.delete();
            _logger.i('Deleted local file: ${chunk.localPath}');
          }
        }

        await box.delete(chunkId);
        _logger.i('Deleted chunk $chunkId from storage');
      }
    } catch (e) {
      _logger.e('Error deleting chunk: $e');
      rethrow;
    }
  }

  /// Cleanup old verified chunks (older than specified days)
  Future<int> cleanupOldVerifiedChunks({int daysOld = 7}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final oldChunks = box.values
          .where(
            (chunk) =>
                chunk.uploadState == ChunkUploadState.verified &&
                chunk.createdAt.isBefore(cutoffDate),
          )
          .toList();

      for (final chunk in oldChunks) {
        await deleteChunk(chunk.chunkId);
      }

      _logger.i('Cleaned up ${oldChunks.length} old verified chunks');
      return oldChunks.length;
    } catch (e) {
      _logger.e('Error cleaning up old chunks: $e');
      rethrow;
    }
  }

  /// Get storage statistics
  Map<String, dynamic> getStorageStats({String? sessionId}) {
    var chunks = box.values.toList();

    if (sessionId != null) {
      chunks = chunks.where((c) => c.sessionId == sessionId).toList();
    }

    return {
      'totalChunks': chunks.length,
      'recorded': chunks
          .where((c) => c.uploadState == ChunkUploadState.recorded)
          .length,
      'uploading': chunks
          .where((c) => c.uploadState == ChunkUploadState.uploading)
          .length,
      'uploaded': chunks
          .where((c) => c.uploadState == ChunkUploadState.uploaded)
          .length,
      'verified': chunks
          .where((c) => c.uploadState == ChunkUploadState.verified)
          .length,
      'failed': chunks
          .where((c) => c.uploadState == ChunkUploadState.failed)
          .length,
      'totalSize': chunks.fold<int>(
        0,
        (sum, chunk) => sum + (chunk.fileSize ?? 0),
      ),
    };
  }

  /// Close the box
  Future<void> close() async {
    await _chunksBox?.close();
    _logger.i('ChunkStorageService closed');
  }

  /// Verify chunk file integrity
  Future<bool> verifyChunkIntegrity(String chunkId) async {
    try {
      final chunk = box.get(chunkId);
      if (chunk == null || chunk.checksum == null) {
        return false;
      }

      final currentChecksum = await calculateChecksum(chunk.localPath);
      final isValid = currentChecksum == chunk.checksum;

      if (!isValid) {
        _logger.w('Chunk $chunkId integrity check failed');
      }

      return isValid;
    } catch (e) {
      _logger.e('Error verifying chunk integrity: $e');
      return false;
    }
  }
}

/// Adapter for ChunkUploadState enum
class ChunkUploadStateAdapter extends TypeAdapter<ChunkUploadState> {
  @override
  final int typeId = 5;

  @override
  ChunkUploadState read(BinaryReader reader) {
    final index = reader.readByte();
    return ChunkUploadState.values[index];
  }

  @override
  void write(BinaryWriter writer, ChunkUploadState obj) {
    writer.writeByte(obj.index);
  }
}
