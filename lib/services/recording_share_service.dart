import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'chunk_storage_service.dart';

/// Service to handle sharing of recording sessions
/// Combines all audio chunks in sequence and presents native share sheet
class RecordingShareService {
  static const MethodChannel _channel = MethodChannel(
    'ai_scribe_copilot/recording_share',
  );

  final ChunkStorageService _storageService;
  final Logger _logger = Logger();

  RecordingShareService(this._storageService);

  /// Share a recording session by combining all chunks
  /// Returns true if share was successful, false otherwise
  Future<bool> shareRecording(String sessionId) async {
    try {
      _logger.i('Starting share for session: $sessionId');

      // Get all chunks for this session from local storage
      final chunks = _storageService.getChunksBySession(sessionId);

      if (chunks.isEmpty) {
        _logger.w('No chunks found for session: $sessionId');
        throw Exception('No audio chunks found for this recording');
      }

      // Sort chunks by sequence number to ensure correct order
      chunks.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

      _logger.i('Found ${chunks.length} chunks in local storage');

      // Get current documents directory to resolve relative paths
      final documentsDir = await getApplicationDocumentsDirectory();
      _logger.i('Current documents directory: ${documentsDir.path}');

      // Debug: List all files in the recording directory
      if (chunks.isNotEmpty) {
        final firstChunkPath = chunks.first.localPath;
        // Try to find the recording directory.
        // stored path example: .../Documents/recordings/<uuid>/chunks/chunk_0.wav
        // parent: .../chunks
        // parent.parent: .../recordings/<uuid>
        final recordingDir = File(firstChunkPath).parent.parent;

        _logger.i(
          'Checking recording directory based on stored path: ${recordingDir.path}',
        );

        try {
          if (await recordingDir.exists()) {
            _logger.i('Recording directory exists, listing contents:');
            await for (final entity in recordingDir.list(recursive: true)) {
              if (entity is File && entity.path.endsWith('.wav')) {
                final size = await entity.length();
                _logger.i('  Found WAV file: ${entity.path} (${size} bytes)');
              }
            }
          } else {
            _logger.w(
              'Recording directory does not exist at path: ${recordingDir.path}',
            );

            // Try to find the Documents directory dynamically to handle iOS container UUID changes
            // This is a common issue on iOS where the absolute path changes between launches
            if (Platform.isIOS) {
              _logger.i('Attempting to resolve current Documents directory...');
              // We can't easily get the "real" documents dir here without path_provider,
              // but we can try to fix the path if we know the relative part.
              // For now, we will rely on the validation loop below to try and find the files.
            }
          }
        } catch (e) {
          _logger.e('Error listing directory: $e');
        }
      }

      // Check if local files exist
      final List<String> validPaths = [];
      final List<int> missingSequences = [];

      for (final chunk in chunks) {
        _logger.i('Checking chunk ${chunk.sequenceNumber}:');
        _logger.i('  Stored path: ${chunk.localPath}');

        File file = File(chunk.localPath);
        bool exists = await file.exists();

        if (!exists) {
          // Try to resolve path relative to current documents directory
          // This handles iOS container UUID changes
          if (chunk.localPath.contains('/Documents/')) {
            final relativePath = chunk.localPath.split('/Documents/').last;
            final newPath = '${documentsDir.path}/$relativePath';

            _logger.i('  Trying resolved path: $newPath');
            final newFile = File(newPath);

            if (await newFile.exists()) {
              _logger.i('  Found file at resolved path');
              file = newFile;
              exists = true;
            }
          }
        }

        if (exists) {
          final size = await file.length();
          _logger.i('  File exists. Size: $size bytes');
          validPaths.add(file.path);
        } else {
          _logger.w(
            '  Chunk ${chunk.sequenceNumber} not found at stored path or resolved path',
          );
          missingSequences.add(chunk.sequenceNumber);
        }
      }

      // If any chunks are missing locally, we cannot share
      if (missingSequences.isNotEmpty) {
        _logger.e('${missingSequences.length} chunks missing locally.');
        throw Exception(
          'Audio chunks ${missingSequences.join(", ")} are missing locally. Cannot share incomplete recording.',
        );
      }

      _logger.i('All ${validPaths.length} chunks available locally, sharing');

      // Call native platform code to combine and share
      final result = await _channel.invokeMethod<bool>('shareRecording', {
        'chunkPaths': validPaths,
        'sessionId': sessionId,
      });

      if (result == true) {
        _logger.i('Recording shared successfully');
        return true;
      } else {
        _logger.w('Share was cancelled or failed');
        return false;
      }
    } on PlatformException catch (e) {
      _logger.e('Platform error while sharing: ${e.message}');
      throw Exception('Failed to share recording: ${e.message}');
    } catch (e) {
      _logger.e('Error sharing recording: $e');
      rethrow;
    }
  }

  /// Get the total size of all chunks for a session
  /// Useful for showing user how large the combined file will be
  Future<int> getSessionTotalSize(String sessionId) async {
    try {
      final chunks = _storageService.getChunksBySession(sessionId);
      int totalSize = 0;

      for (final chunk in chunks) {
        final file = File(chunk.localPath);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      _logger.e('Error calculating session size: $e');
      return 0;
    }
  }

  /// Format bytes to human readable string
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
