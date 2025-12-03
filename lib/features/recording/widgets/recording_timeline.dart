import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/audio_chunk.dart';
import '../../../providers/recording_providers.dart';
import '../../../providers/service_providers.dart';

class RecordingTimeline extends ConsumerStatefulWidget {
  const RecordingTimeline({super.key});

  @override
  ConsumerState<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends ConsumerState<RecordingTimeline> {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  bool _userIsScrolling = false;

  // Constants for layout
  static const double _pixelsPerSecond = 20.0;
  static const double _rulerHeight = 30.0;
  static const double _recordingTrackHeight = 30.0;
  static const double _chunkTrackHeight = 60.0;
  static const double _timelineHeight = 160.0;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_userIsScrolling && mounted) {
        final recordingState = ref.read(recordingSessionProvider);
        if (recordingState.isRecording && !recordingState.isPaused) {
          _scrollToCurrentTime(recordingState.currentDuration);
        }
      }
    });
  }

  void _scrollToCurrentTime(Duration currentDuration) {
    if (!_scrollController.hasClients) return;

    final targetOffset =
        (currentDuration.inMilliseconds / 1000) * _pixelsPerSecond -
        (MediaQuery.of(context).size.width / 2);

    // Smooth scroll if the jump is small, otherwise jump
    if ((_scrollController.offset - targetOffset).abs() < 100) {
      _scrollController.animateTo(
        targetOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent + 500,
        ), // Allow overscroll
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
    } else {
      _scrollController.jumpTo(
        targetOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent + 500,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingSessionProvider);
    final chunks = ref.watch(currentSessionChunksProvider);
    final currentDuration = recordingState.currentDuration;

    // Calculate total width based on duration + some buffer
    final totalSeconds = currentDuration.inSeconds + 10; // +10s buffer
    final totalWidth = totalSeconds * _pixelsPerSecond;
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate total chunk duration to ensure bar covers all chunks
    double totalChunkSeconds = 0;
    for (var c in chunks) {
      double d = (c.duration?.inMilliseconds ?? 0) / 1000.0;
      if (d <= 0 && c.fileSize != null && c.fileSize! > 0) {
        d = c.fileSize! / 32000.0;
      }
      if (d <= 0) d = 5.0;
      totalChunkSeconds += d;
    }

    final currentSeconds = currentDuration.inMilliseconds / 1000.0;
    final displaySeconds = currentSeconds > totalChunkSeconds
        ? currentSeconds
        : totalChunkSeconds;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _userIsScrolling = true;
        } else if (notification is ScrollEndNotification) {
          // Resume auto-scrolling after a delay if user stops interacting
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _userIsScrolling = false;
              });
            }
          });
        }
        return false;
      },
      child: SizedBox(
        height: _timelineHeight,
        child: Stack(
          children: [
            // Scrolling Content
            SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                width: totalWidth < screenWidth ? screenWidth : totalWidth,
                height: _timelineHeight,
                child: Stack(
                  children: [
                    // 1. Time Ruler (Background)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: _rulerHeight,
                      child: CustomPaint(
                        painter: _TimeRulerPainter(
                          pixelsPerSecond: _pixelsPerSecond,
                          totalSeconds: totalSeconds,
                          theme: Theme.of(context),
                        ),
                      ),
                    ),

                    // 2. Recording Track (Continuous)
                    Positioned(
                      top: _rulerHeight,
                      left: 0,
                      height: _recordingTrackHeight,
                      width: totalWidth,
                      child: Stack(
                        children: [
                          // Background track
                          Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.3),
                          ),
                          // Active recording progress
                          if (displaySeconds > 0)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: displaySeconds * _pixelsPerSecond,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.3),
                                border: Border(
                                  right: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // 3. Chunk Track
                    Positioned(
                      top: _rulerHeight + _recordingTrackHeight,
                      left: 0,
                      right: 0,
                      height: _chunkTrackHeight,
                      child: Stack(
                        children: chunks.map((chunk) {
                          // Helper to get duration
                          double getChunkDuration(AudioChunk c) {
                            double d =
                                (c.duration?.inMilliseconds ?? 0) / 1000.0;
                            if (d > 0) return d;

                            if (c.fileSize != null && c.fileSize! > 0) {
                              // 16kHz, 16-bit (2 bytes), mono = 32000 bytes/sec
                              return c.fileSize! / 32000.0;
                            }

                            return 5.0; // Default fallback
                          }

                          double startSeconds = 0;
                          for (var c in chunks) {
                            if (c.sequenceNumber < chunk.sequenceNumber) {
                              startSeconds += getChunkDuration(c);
                            }
                          }

                          final durationSeconds = getChunkDuration(chunk);
                          final width = durationSeconds * _pixelsPerSecond;

                          return Positioned(
                            left: startSeconds * _pixelsPerSecond,
                            width: width,
                            top: 5,
                            bottom: 5,
                            child: _ChunkBlock(chunk: chunk),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Center Line Indicator (Static overlay)
            // Positioned(
            //   left: screenWidth / 2,
            //   top: 0,
            //   bottom: 0,
            //   width: 2,
            //   child: Container(color: Colors.red),
            // ),

            // "Return to Live" button if scrolled away
            if (_userIsScrolling)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() {
                      _userIsScrolling = false;
                    });
                    _scrollToCurrentTime(recordingState.currentDuration);
                  },
                  child: const Icon(Icons.arrow_forward),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChunkBlock extends StatelessWidget {
  final AudioChunk chunk;

  const _ChunkBlock({required this.chunk});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (chunk.uploadState) {
      case ChunkUploadState.recorded:
        color = Colors.grey;
        icon = Icons.hourglass_empty;
        label = "Wait";
        break;
      case ChunkUploadState.uploading:
        color = Colors.blue;
        icon = Icons.cloud_upload;
        label = "Up";
        break;
      case ChunkUploadState.uploaded:
        color = Colors.green;
        icon = Icons.check;
        label = "Done";
        break;
      case ChunkUploadState.verified:
        color = Colors.teal;
        icon = Icons.verified;
        label = "OK";
        break;
      case ChunkUploadState.failed:
        color = Colors.red;
        icon = Icons.error;
        label = "Fail";
        break;
    }

    return Tooltip(
      message: "Chunk #${chunk.sequenceNumber}\nStatus: $label",
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(1.0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            Text(
              "#${chunk.sequenceNumber}",
              style: const TextStyle(color: Colors.white, fontSize: 8),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final int totalSeconds;
  final ThemeData theme;

  _TimeRulerPainter({
    required this.pixelsPerSecond,
    required this.totalSeconds,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          theme.textTheme.bodySmall?.color?.withOpacity(0.5) ?? Colors.grey
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (int i = 0; i <= totalSeconds; i++) {
      final x = i * pixelsPerSecond;

      // Draw major ticks every 10 seconds, minor every 1 second
      if (i % 10 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, 15), paint);

        // Draw time label
        final timeStr = _formatTime(i);
        textPainter.text = TextSpan(
          text: timeStr,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
        );
        textPainter.layout();

        // Adjust x position to prevent clipping at the start
        double textX = x - textPainter.width / 2;
        if (x == 0) {
          textX = 0; // Align left edge to 0
        }

        textPainter.paint(canvas, Offset(textX, 18));
      } else if (i % 2 == 0) {
        // Minor ticks every 2 seconds to reduce clutter
        canvas.drawLine(Offset(x, 0), Offset(x, 8), paint);
      }
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
