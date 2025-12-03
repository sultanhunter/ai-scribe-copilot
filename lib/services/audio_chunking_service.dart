import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_chunk.dart';

/// Service to chunk a continuously recording audio file in parallel
class AudioChunkingService {
  final Logger _logger = Logger();
  final _uuid = const Uuid();

  Timer? _chunkingTimer;
  String? _currentSessionId;
  String? _recordingFilePath;
  int _nextSequenceNumber = 0;
  int _lastChunkedPosition = 0; // Byte position of last chunk created
  bool _isChunking = false;
  int? _audioDataOffset; // Offset where audio data starts in the source file

  final StreamController<AudioChunk> _chunkController =
      StreamController<AudioChunk>.broadcast();

  Stream<AudioChunk> get chunkStream => _chunkController.stream;

  /// Start monitoring and chunking the recording file
  Future<void> startChunking({
    required String sessionId,
    required String recordingFilePath,
    int startingSequenceNumber = 0,
  }) async {
    try {
      _currentSessionId = sessionId;
      _recordingFilePath = recordingFilePath;
      _nextSequenceNumber = startingSequenceNumber;
      _audioDataOffset = null; // Reset offset
      _lastChunkedPosition = 0; // Will be calculated once we find the offset
      _isChunking = true;

      _logger.i(
        'Started chunking service for session: $sessionId, '
        'starting from sequence: $startingSequenceNumber',
      );

      // Start periodic checking and chunking
      _startChunkingTimer();
    } catch (e) {
      _logger.e('Error starting chunking service: $e');
      rethrow;
    }
  }

  void _startChunkingTimer() {
    _chunkingTimer?.cancel();
    // Check for new chunks every 2 seconds (more frequent than chunk duration)
    _chunkingTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _processChunks(),
    );
  }

  /// Calculate byte position for a given sequence number
  int _calculateStartPosition(int sequenceNumber) {
    if (_audioDataOffset == null) return 0;

    // Calculate bytes per chunk based on duration
    // sampleRate * channels * bytesPerSample * duration
    final bytesPerChunk =
        AppConstants.audioSampleRate *
        1 * // mono
        2 * // 16-bit = 2 bytes
        AppConstants.audioChunkDurationSeconds;

    return _audioDataOffset! + (bytesPerChunk * sequenceNumber);
  }

  /// Find the offset of the 'data' chunk in a WAV file
  Future<int?> _findAudioDataOffset(File file) async {
    try {
      final randomAccess = await file.open();
      final length = await file.length();

      // Read first 12 bytes (RIFF header)
      await randomAccess.setPosition(0);
      final riffHeader = await randomAccess.read(12);

      // Check for RIFF and WAVE tags
      final riff = String.fromCharCodes(riffHeader.sublist(0, 4));
      final wave = String.fromCharCodes(riffHeader.sublist(8, 12));

      if (riff != 'RIFF' || wave != 'WAVE') {
        _logger.w('Invalid WAV header: $riff, $wave');
        await randomAccess.close();
        return null;
      }

      // Start searching for 'data' chunk from byte 12
      int position = 12;

      while (position + 8 <= length) {
        await randomAccess.setPosition(position);
        final chunkHeader = await randomAccess.read(8);
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = chunkHeader.buffer.asByteData().getUint32(
          4,
          Endian.little,
        );

        if (chunkId == 'data') {
          await randomAccess.close();
          // The audio data starts after the chunk ID (4 bytes) and size (4 bytes)
          return position + 8;
        }

        // Move to next chunk
        position += 8 + chunkSize;
      }

      await randomAccess.close();
      return null;
    } catch (e) {
      _logger.e('Error parsing WAV header: $e');
      return null;
    }
  }

  /// Process and create chunks from the recording file
  Future<void> _processChunks() async {
    if (!_isChunking ||
        _recordingFilePath == null ||
        _currentSessionId == null) {
      return;
    }

    try {
      final recordingFile = File(_recordingFilePath!);
      if (!await recordingFile.exists()) {
        _logger.w('Recording file does not exist yet');
        return;
      }

      // If we haven't found the data offset yet, try to find it
      if (_audioDataOffset == null) {
        final offset = await _findAudioDataOffset(recordingFile);
        if (offset == null) {
          // Not ready yet or invalid file
          return;
        }

        _audioDataOffset = offset;
        _logger.i('Found audio data offset at: $_audioDataOffset');

        // Always start from the beginning of the audio data for a new file
        // regardless of sequence number (since this is a new file segment)
        _lastChunkedPosition = _audioDataOffset!;
      }

      final fileSize = await recordingFile.length();

      // Calculate how much audio data is available
      final availableAudioBytes = fileSize - _audioDataOffset!;

      // Calculate bytes per chunk
      final bytesPerChunk =
          AppConstants.audioSampleRate *
          1 * // mono
          2 * // 16-bit
          AppConstants.audioChunkDurationSeconds;

      // Check if we have enough data for a new chunk
      final chunkedAudioBytes = _lastChunkedPosition - _audioDataOffset!;
      final unprocessedBytes = availableAudioBytes - chunkedAudioBytes;

      if (unprocessedBytes >= bytesPerChunk) {
        // We have enough data for at least one chunk
        final chunksToCreate = unprocessedBytes ~/ bytesPerChunk;

        for (int i = 0; i < chunksToCreate; i++) {
          await _createChunkFromFile(
            recordingFile,
            _lastChunkedPosition,
            bytesPerChunk,
          );

          _lastChunkedPosition += bytesPerChunk;
          _nextSequenceNumber++;
        }
      }
    } catch (e) {
      _logger.e('Error processing chunks: $e');
    }
  }

  /// Create a chunk file from a portion of the recording file
  Future<void> _createChunkFromFile(
    File recordingFile,
    int startPosition,
    int chunkSize,
  ) async {
    try {
      // Read chunk audio data
      final randomAccess = await recordingFile.open();
      await randomAccess.setPosition(startPosition);
      final audioData = await randomAccess.read(chunkSize);
      await randomAccess.close();

      // Create chunk file
      final chunkDir = '${recordingFile.parent.path}/chunks';
      await Directory(chunkDir).create(recursive: true);

      final chunkPath = '$chunkDir/chunk_$_nextSequenceNumber.wav';
      final chunkFile = File(chunkPath);

      // Generate a clean standard WAV header
      final header = _generateWavHeader(audioData.length);
      final chunkData = Uint8List.fromList([...header, ...audioData]);

      await chunkFile.writeAsBytes(chunkData);

      // Calculate duration
      final durationSeconds =
          chunkData.length /
          (AppConstants.audioSampleRate *
              1 *
              2); // SampleRate * Channels * BytesPerSample
      final duration = Duration(
        microseconds: (durationSeconds * 1000000).round(),
      );

      // Create chunk metadata
      final chunk = AudioChunk(
        chunkId: _uuid.v4(),
        sessionId: _currentSessionId!,
        sequenceNumber: _nextSequenceNumber,
        localPath: chunkPath,
        fileSize: chunkData.length,
        uploadState: ChunkUploadState.recorded,
        duration: duration,
      );

      _chunkController.add(chunk);
      _logger.i(
        'Chunk created: ${chunk.chunkId}, sequence: $_nextSequenceNumber, '
        'size: ${chunk.fileSize} bytes',
      );
    } catch (e) {
      _logger.e('Error creating chunk file: $e');
      rethrow;
    }
  }

  /// Generate a standard 44-byte WAV header
  Uint8List _generateWavHeader(int audioDataSize) {
    final header = Uint8List(44);
    final view = ByteData.view(header.buffer);

    // RIFF chunk
    header.setRange(0, 4, 'RIFF'.codeUnits);
    view.setUint32(4, 36 + audioDataSize, Endian.little); // File size - 8
    header.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt chunk
    header.setRange(12, 16, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little); // Chunk size (16 for PCM)
    view.setUint16(20, 1, Endian.little); // Audio format (1 for PCM)
    view.setUint16(22, 1, Endian.little); // Num channels (1 for mono)
    view.setUint32(
      24,
      AppConstants.audioSampleRate,
      Endian.little,
    ); // Sample rate
    view.setUint32(
      28,
      AppConstants.audioSampleRate * 2,
      Endian.little,
    ); // Byte rate (SampleRate * NumChannels * BitsPerSample/8)
    view.setUint16(
      32,
      2,
      Endian.little,
    ); // Block align (NumChannels * BitsPerSample/8)
    view.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    header.setRange(36, 40, 'data'.codeUnits);
    view.setUint32(40, audioDataSize, Endian.little); // Data size

    return header;
  }

  /// Stop chunking and process any remaining audio
  Future<void> stopChunking() async {
    try {
      _chunkingTimer?.cancel();
      _isChunking = false;

      // Process any remaining audio data
      if (_recordingFilePath != null && _currentSessionId != null) {
        await _processRemainingAudio();
      }

      _logger.i('Chunking stopped, processed all remaining audio');
    } catch (e) {
      _logger.e('Error stopping chunking: $e');
      rethrow;
    }
  }

  /// Process remaining audio that's less than a full chunk
  Future<void> _processRemainingAudio() async {
    try {
      final recordingFile = File(_recordingFilePath!);
      if (!await recordingFile.exists()) {
        return;
      }

      // Ensure we have the offset
      if (_audioDataOffset == null) {
        _audioDataOffset = await _findAudioDataOffset(recordingFile);
        if (_audioDataOffset == null) return;

        // If we just found the offset, update the start position
        if (_lastChunkedPosition == 0) {
          _lastChunkedPosition = _calculateStartPosition(_nextSequenceNumber);
        }
      }

      final fileSize = await recordingFile.length();
      final availableAudioBytes = fileSize - _audioDataOffset!;
      final chunkedAudioBytes = _lastChunkedPosition - _audioDataOffset!;
      final remainingBytes = availableAudioBytes - chunkedAudioBytes;

      if (remainingBytes > 0) {
        _logger.i('Processing $remainingBytes bytes of remaining audio');

        // Create final chunk with remaining audio
        await _createChunkFromFile(
          recordingFile,
          _lastChunkedPosition,
          remainingBytes,
        );

        _logger.i('Created final chunk with remaining audio');
      }
    } catch (e) {
      _logger.e('Error processing remaining audio: $e');
    }
  }

  /// Get the recording file path
  String? get recordingFilePath => _recordingFilePath;

  /// Get current chunking progress
  Map<String, dynamic> getProgress() {
    return {
      'sessionId': _currentSessionId,
      'nextSequenceNumber': _nextSequenceNumber,
      'lastChunkedPosition': _lastChunkedPosition,
      'isChunking': _isChunking,
    };
  }

  void dispose() {
    _chunkingTimer?.cancel();
    _chunkController.close();
  }
}
