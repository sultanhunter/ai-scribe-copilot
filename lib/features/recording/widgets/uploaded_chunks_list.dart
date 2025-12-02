import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../providers/recording_providers.dart';
import '../../../providers/service_providers.dart';

// Provider for managing uploaded chunks state
class UploadedChunksNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() => [];

  void setChunks(List<Map<String, dynamic>> chunks) {
    state = chunks;
  }
}

class LoadingStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) {
    state = loading;
  }
}

final uploadedChunksProvider =
    NotifierProvider<UploadedChunksNotifier, List<Map<String, dynamic>>>(
      UploadedChunksNotifier.new,
    );

final isLoadingUploadedChunksProvider =
    NotifierProvider<LoadingStateNotifier, bool>(LoadingStateNotifier.new);

class UploadedChunksList extends ConsumerStatefulWidget {
  const UploadedChunksList({super.key});

  @override
  ConsumerState<UploadedChunksList> createState() => _UploadedChunksListState();
}

class _UploadedChunksListState extends ConsumerState<UploadedChunksList> {
  String? _lastLoadedSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUploadedChunks();
    });
  }

  Future<void> _loadUploadedChunks({bool forceRefresh = false}) async {
    final recordingState = ref.read(recordingSessionProvider);

    // If no session exists, clear the chunks
    if (recordingState.session?.sessionId == null) {
      ref.read(uploadedChunksProvider.notifier).setChunks([]);
      _lastLoadedSessionId = null;
      return;
    }

    // Don't reload if we already have data for this session (unless force refresh)
    if (!forceRefresh &&
        _lastLoadedSessionId == recordingState.session!.sessionId &&
        ref.read(uploadedChunksProvider).isNotEmpty) {
      return;
    }

    _lastLoadedSessionId = recordingState.session!.sessionId;
    ref.read(isLoadingUploadedChunksProvider.notifier).setLoading(true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final chunks = await apiService.getUploadedChunks(
        recordingState.session!.sessionId,
      );
      ref.read(uploadedChunksProvider.notifier).setChunks(chunks);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading chunks: $e')));
      }
    } finally {
      ref.read(isLoadingUploadedChunksProvider.notifier).setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chunks = ref.watch(uploadedChunksProvider);
    final isLoading = ref.watch(isLoadingUploadedChunksProvider);

    // Watch the recording session and reload chunks when session changes
    ref.listen<RecordingSessionState>(recordingSessionProvider, (
      previous,
      next,
    ) {
      // If session changed, reload chunks
      if (next.session?.sessionId != previous?.session?.sessionId) {
        _loadUploadedChunks();
      }
    });

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploaded Chunks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    if (isLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: () =>
                            _loadUploadedChunks(forceRefresh: true),
                        tooltip: 'Refresh',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${chunks.length} chunks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (chunks.isEmpty && !isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No uploaded chunks yet',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: chunks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final chunk = chunks[index];
                  return UploadedChunkTile(
                    chunk: chunk,
                    onRefresh: _loadUploadedChunks,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class UploadedChunkTile extends StatefulWidget {
  final Map<String, dynamic> chunk;
  final VoidCallback onRefresh;

  const UploadedChunkTile({
    super.key,
    required this.chunk,
    required this.onRefresh,
  });

  @override
  State<UploadedChunkTile> createState() => _UploadedChunkTileState();
}

class _UploadedChunkTileState extends State<UploadedChunkTile> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // Store subscriptions so we can cancel them
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  @override
  void dispose() {
    // Cancel all subscriptions before disposing
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (widget.chunk['signedUrl'] == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Audio URL not available')));
      return;
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.chunk['signedUrl']));
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Play/Pause Button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.green,
                    size: 20,
                  ),
                  onPressed: _togglePlayPause,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              // Chunk Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Chunk #${widget.chunk['sequenceNumber']}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Uploaded',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.storage,
                          size: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatFileSize(widget.chunk['fileSize']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_duration.inSeconds > 0) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.timer,
                            size: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(_duration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Progress bar
          if (_isPlaying || _position.inSeconds > 0) ...[
            const SizedBox(height: 8),
            Column(
              children: [
                LinearProgressIndicator(
                  value: _duration.inSeconds > 0
                      ? _position.inSeconds / _duration.inSeconds
                      : 0,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
