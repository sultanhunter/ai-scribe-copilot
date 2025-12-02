import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_chunk.dart';
import 'api_service.dart';
import 'chunk_storage_service.dart';

class ChunkUploadService {
  final ApiService _apiService;
  final ChunkStorageService _storageService;
  final Logger _logger = Logger();

  bool _isProcessing = false;
  Timer? _queueProcessingTimer;

  final StreamController<ChunkUploadProgress> _progressController =
      StreamController<ChunkUploadProgress>.broadcast();

  Stream<ChunkUploadProgress> get progressStream => _progressController.stream;

  ChunkUploadService(this._apiService, this._storageService);

  /// Start background queue processing
  void startQueueProcessing() {
    _queueProcessingTimer?.cancel();
    _queueProcessingTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _processQueue(),
    );
  }

  /// Stop background queue processing
  void stopQueueProcessing() {
    _queueProcessingTimer?.cancel();
  }

  /// Add chunk to upload queue
  Future<void> uploadChunk(AudioChunk chunk) async {
    try {
      // Save to persistent storage
      await _storageService.saveChunk(chunk);
      _logger.i('Chunk ${chunk.chunkId} added to upload queue');

      // Trigger queue processing
      _processQueue();
    } catch (e) {
      _logger.e('Error adding chunk to queue: $e');
      rethrow;
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;

    try {
      _isProcessing = true;

      // Get all pending chunks from storage
      final pendingChunks = _storageService.getPendingChunks();

      if (pendingChunks.isEmpty) {
        _isProcessing = false;
        return;
      }

      _logger.i('Processing ${pendingChunks.length} pending chunks');

      for (final chunk in pendingChunks) {
        try {
          // Skip if already uploading
          if (chunk.uploadState == ChunkUploadState.uploading) {
            continue;
          }

          // Mark as failed if max retries exceeded
          if (chunk.retryCount >= AppConstants.maxRetryAttempts) {
            await _storageService.updateChunkState(
              chunk.chunkId,
              ChunkUploadState.failed,
              errorMessage:
                  'Max retry attempts (${AppConstants.maxRetryAttempts}) exceeded',
            );
            _emitProgress(
              chunk,
              UploadStatus.failed,
              error: 'Max retry attempts exceeded',
            );
            continue;
          }

          // Verify file integrity before upload
          if (!await _storageService.verifyChunkIntegrity(chunk.chunkId)) {
            await _storageService.updateChunkState(
              chunk.chunkId,
              ChunkUploadState.failed,
              errorMessage: 'File integrity check failed',
            );
            _emitProgress(
              chunk,
              UploadStatus.failed,
              error: 'File integrity check failed',
            );
            continue;
          }

          // Upload the chunk
          await _uploadSingleChunk(chunk);

          // Mark as uploaded after successful upload
          await _storageService.updateChunkState(
            chunk.chunkId,
            ChunkUploadState.uploaded,
          );

          _emitProgress(chunk, UploadStatus.success);
        } catch (e) {
          _logger.e('Error uploading chunk ${chunk.chunkId}: $e');

          // Increment retry count
          await _storageService.incrementRetryCount(chunk.chunkId);

          final retries = chunk.retryCount + 1;

          if (retries <= AppConstants.maxRetryAttempts) {
            // Mark for retry
            await _storageService.updateChunkState(
              chunk.chunkId,
              ChunkUploadState.recorded,
              errorMessage: e.toString(),
            );

            _emitProgress(chunk, UploadStatus.retrying, retryCount: retries);

            // Wait before retrying with exponential backoff
            await Future.delayed(
              Duration(
                seconds: (AppConstants.retryDelaySeconds * (retries + 1))
                    .toInt(),
              ),
            );
          } else {
            // Max retries exceeded
            await _storageService.updateChunkState(
              chunk.chunkId,
              ChunkUploadState.failed,
              errorMessage: 'Max retries exceeded: ${e.toString()}',
            );

            _emitProgress(chunk, UploadStatus.failed, error: e.toString());
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _emitProgress(
    AudioChunk chunk,
    UploadStatus status, {
    int? retryCount,
    String? error,
  }) {
    final queueSize = _storageService.getPendingChunks().length;
    _progressController.add(
      ChunkUploadProgress(
        chunkId: chunk.chunkId,
        sequenceNumber: chunk.sequenceNumber,
        status: status,
        retryCount: retryCount,
        error: error,
        queueSize: queueSize,
      ),
    );
  }

  Future<void> _uploadSingleChunk(AudioChunk chunk) async {
    _logger.i(
      'Uploading chunk: ${chunk.chunkId}, sequence: ${chunk.sequenceNumber}',
    );

    // Update state to uploading
    await _storageService.updateChunkState(
      chunk.chunkId,
      ChunkUploadState.uploading,
    );

    _emitProgress(chunk, UploadStatus.uploading);

    // Step 1: Get presigned URL
    final presignedUrl = await _apiService.getPresignedUrl(
      sessionId: chunk.sessionId,
      chunkId: chunk.chunkId,
      sequenceNumber: chunk.sequenceNumber,
    );

    // Step 2: Read file
    final file = File(chunk.localPath);
    if (!await file.exists()) {
      throw Exception('Chunk file not found: ${chunk.localPath}');
    }

    final fileBytes = await file.readAsBytes();

    // Step 3: Upload to presigned URL
    await _apiService.uploadChunk(presignedUrl, fileBytes);

    // Step 4: Notify backend with checksum
    await _apiService.notifyChunkUploaded(
      sessionId: chunk.sessionId,
      chunkId: chunk.chunkId,
      sequenceNumber: chunk.sequenceNumber,
      checksum: chunk.checksum,
    );

    _logger.i('Successfully uploaded chunk: ${chunk.chunkId}');
  }

  int get queueSize => _storageService.getPendingChunks().length;

  List<AudioChunk> get pendingChunks => _storageService.getPendingChunks();

  /// Verify and mark chunk as verified after server confirmation
  Future<void> verifyChunk(String chunkId) async {
    await _storageService.updateChunkState(chunkId, ChunkUploadState.verified);
    _logger.i('Chunk $chunkId verified');
  }

  /// Resume uploads for all pending chunks
  Future<void> resumePendingUploads() async {
    final pending = _storageService.getPendingChunks();
    _logger.i('Resuming ${pending.length} pending uploads');

    if (pending.isNotEmpty) {
      await _processQueue();
    }
  }

  /// Retry all failed chunks
  Future<int> retryFailedChunks() async {
    final count = await _storageService.retryAllFailedChunks();
    _logger.i('Retrying $count failed chunks');

    if (count > 0) {
      // Trigger queue processing for newly reset chunks
      _processQueue();
    }

    return count;
  }

  /// Retry a specific failed chunk
  Future<void> retrySingleChunk(String chunkId) async {
    await _storageService.resetRetryCount(chunkId);
    await _storageService.updateChunkState(chunkId, ChunkUploadState.recorded);
    _logger.i('Reset chunk $chunkId for retry');

    // Trigger queue processing
    _processQueue();
  }

  void dispose() {
    _queueProcessingTimer?.cancel();
    _progressController.close();
  }
}

class ChunkUploadProgress {
  final String chunkId;
  final int sequenceNumber;
  final UploadStatus status;
  final int? retryCount;
  final String? error;
  final int queueSize;

  ChunkUploadProgress({
    required this.chunkId,
    required this.sequenceNumber,
    required this.status,
    this.retryCount,
    this.error,
    required this.queueSize,
  });
}

enum UploadStatus { uploading, success, failed, retrying }
