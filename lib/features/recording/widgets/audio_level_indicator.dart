import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Visual indicator for real-time audio levels
class AudioLevelIndicator extends StatelessWidget {
  final double level; // 0.0 to 1.0
  final int barCount;
  final double height;
  final double barWidth;
  final double spacing;

  const AudioLevelIndicator({
    super.key,
    required this.level,
    this.barCount = 20,
    this.height = 60,
    this.barWidth = 4,
    this.spacing = 3,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(barCount, (index) {
          // Calculate which bars should be active based on current level
          final barThreshold = (index + 1) / barCount;
          final isActive = level >= barThreshold;

          // Calculate bar height with some randomness for visual effect
          final baseHeight = height * 0.3;
          final maxHeight = height;
          final barHeight = isActive
              ? baseHeight + (maxHeight - baseHeight) * (index / barCount)
              : baseHeight * 0.5;

          // Color based on level (green -> yellow -> red)
          Color barColor;
          if (index < barCount * 0.6) {
            barColor = Colors.green;
          } else if (index < barCount * 0.85) {
            barColor = Colors.orange;
          } else {
            barColor = Colors.red;
          }

          return Container(
            width: barWidth,
            height: barHeight,
            margin: EdgeInsets.symmetric(horizontal: spacing / 2),
            decoration: BoxDecoration(
              color: isActive
                  ? barColor
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(barWidth / 2),
            ),
          );
        }),
      ),
    );
  }
}

/// Animated waveform-style audio level indicator
class WaveformAudioIndicator extends StatelessWidget {
  final double level; // 0.0 to 1.0
  final int barCount;
  final double height;

  const WaveformAudioIndicator({
    super.key,
    required this.level,
    this.barCount = 30,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(
          level: level,
          barCount: barCount,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double level;
  final int barCount;
  final Color color;
  final Color backgroundColor;

  _WaveformPainter({
    required this.level,
    required this.barCount,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / barCount;
    final centerY = size.height / 2;

    final activePaint = Paint()
      ..color = color
      ..strokeWidth = barWidth * 0.7
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = barWidth * 0.7
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barWidth / 2;

      // Create wave pattern
      final waveOffset = math.sin((i / barCount) * math.pi * 2) * 0.3;
      final normalizedIndex = (i / barCount) + waveOffset;

      // Calculate bar height based on level
      final barThreshold = normalizedIndex.clamp(0.0, 1.0);
      final isActive = level >= barThreshold;

      final barHeight = isActive
          ? (size.height * 0.8) * level * (0.5 + normalizedIndex * 0.5)
          : size.height * 0.1;

      final paint = isActive ? activePaint : inactivePaint;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}

/// Circular audio level indicator
class CircularAudioIndicator extends StatelessWidget {
  final double level; // 0.0 to 1.0
  final double size;

  const CircularAudioIndicator({
    super.key,
    required this.level,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Color based on level
    Color indicatorColor;
    if (level < 0.6) {
      indicatorColor = Colors.green;
    } else if (level < 0.85) {
      indicatorColor = Colors.orange;
    } else {
      indicatorColor = Colors.red;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          CircularProgressIndicator(
            value: 1.0,
            strokeWidth: 8,
            valueColor: AlwaysStoppedAnimation(
              theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          // Level indicator
          CircularProgressIndicator(
            value: level,
            strokeWidth: 8,
            valueColor: AlwaysStoppedAnimation(indicatorColor),
          ),
          // Center icon
          Icon(
            Icons.mic,
            size: size * 0.4,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ],
      ),
    );
  }
}
