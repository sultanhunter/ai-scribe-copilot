import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_chunk.dart';
import 'api_service.dart';

class ChunkUploadService {
  final ApiService _apiService;
  final Logger _logger = Logger();

  final List<AudioChunk> _uploadQueue = [];
  final Map<String, int> _retryCount = {};
  bool _isUploading = false;

  final StreamController<ChunkUploadProgress> _progressController =
      StreamController<ChunkUploadProgress>.broadcast();

  Stream<ChunkUploadProgress> get progressStream => _progressController.stream;

  ChunkUploadService(this._apiService);

  Future<void> uploadChunk(AudioChunk chunk) async {
    _uploadQueue.add(chunk);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isUploading || _uploadQueue.isEmpty) return;

    _isUploading = true;

    while (_uploadQueue.isNotEmpty) {
      final chunk = _uploadQueue.first;

      try {
        await _uploadSingleChunk(chunk);
        _uploadQueue.removeAt(0);
        _retryCount.remove(chunk.chunkId);

        _progressController.add(
          ChunkUploadProgress(
            chunkId: chunk.chunkId,
            sequenceNumber: chunk.sequenceNumber,
            status: UploadStatus.success,
            queueSize: _uploadQueue.length,
          ),
        );
      } catch (e) {
        _logger.e('Error uploading chunk ${chunk.chunkId}: $e');

        final retries = _retryCount[chunk.chunkId] ?? 0;

        if (retries < AppConstants.maxRetryAttempts) {
          _retryCount[chunk.chunkId] = retries + 1;
          _uploadQueue.removeAt(0);
          _uploadQueue.add(chunk); // Re-add to end of queue

          _progressController.add(
            ChunkUploadProgress(
              chunkId: chunk.chunkId,
              sequenceNumber: chunk.sequenceNumber,
              status: UploadStatus.retrying,
              retryCount: retries + 1,
              queueSize: _uploadQueue.length,
            ),
          );

          // Wait before retry with exponential backoff
          await Future.delayed(
            Duration(seconds: AppConstants.retryDelaySeconds * (retries + 1)),
          );
        } else {
          _uploadQueue.removeAt(0);
          _retryCount.remove(chunk.chunkId);

          _progressController.add(
            ChunkUploadProgress(
              chunkId: chunk.chunkId,
              sequenceNumber: chunk.sequenceNumber,
              status: UploadStatus.failed,
              error: e.toString(),
              queueSize: _uploadQueue.length,
            ),
          );
        }
      }
    }

    _isUploading = false;
  }

  Future<void> _uploadSingleChunk(AudioChunk chunk) async {
    _logger.i(
      'Uploading chunk: ${chunk.chunkId}, sequence: ${chunk.sequenceNumber}',
    );

    _progressController.add(
      ChunkUploadProgress(
        chunkId: chunk.chunkId,
        sequenceNumber: chunk.sequenceNumber,
        status: UploadStatus.uploading,
        queueSize: _uploadQueue.length,
      ),
    );

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

    // Step 4: Notify backend
    await _apiService.notifyChunkUploaded(
      sessionId: chunk.sessionId,
      chunkId: chunk.chunkId,
      sequenceNumber: chunk.sequenceNumber,
    );

    _logger.i('Successfully uploaded chunk: ${chunk.chunkId}');
  }

  int get queueSize => _uploadQueue.length;

  List<AudioChunk> get pendingChunks => List.unmodifiable(_uploadQueue);

  void dispose() {
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
