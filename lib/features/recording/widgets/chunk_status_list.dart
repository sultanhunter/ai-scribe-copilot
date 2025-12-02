import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/audio_chunk.dart';
import '../../../providers/service_providers.dart';

class ChunkStatusList extends ConsumerWidget {
  const ChunkStatusList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chunks = ref.watch(currentSessionChunksProvider);

    if (chunks.isEmpty) {
      return const SizedBox.shrink();
    }

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
                  'Chunk Upload Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: chunks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final chunk = chunks[index];
                return ChunkStatusTile(chunk: chunk);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChunkStatusTile extends ConsumerWidget {
  final AudioChunk chunk;

  const ChunkStatusTile({super.key, required this.chunk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusInfo = _getStatusInfo(chunk.uploadState);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusInfo.backgroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusInfo.color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          // Status Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusInfo.backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(statusInfo.icon, color: statusInfo.color, size: 20),
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
                      'Chunk #${chunk.sequenceNumber}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusInfo.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusInfo.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (chunk.fileSize != null) ...[
                      Icon(
                        Icons.storage,
                        size: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatFileSize(chunk.fileSize!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (chunk.retryCount > 0) ...[
                      Icon(Icons.refresh, size: 12, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'Retry: ${chunk.retryCount}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(chunk.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Progress Indicator for uploading state or Retry button for failed
          if (chunk.uploadState == ChunkUploadState.uploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (chunk.uploadState == ChunkUploadState.failed)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              color: Colors.orange,
              tooltip: 'Retry upload',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () async {
                final uploadService = ref.read(chunkUploadServiceProvider);
                await uploadService.retrySingleChunk(chunk.chunkId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Retrying chunk #${chunk.sequenceNumber}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  _StatusInfo _getStatusInfo(ChunkUploadState state) {
    switch (state) {
      case ChunkUploadState.recorded:
        return _StatusInfo(
          icon: Icons.pending,
          label: 'Pending',
          color: Colors.grey,
          backgroundColor: Colors.grey.withOpacity(0.2),
        );
      case ChunkUploadState.uploading:
        return _StatusInfo(
          icon: Icons.cloud_upload,
          label: 'Uploading',
          color: Colors.blue,
          backgroundColor: Colors.blue.withOpacity(0.2),
        );
      case ChunkUploadState.uploaded:
        return _StatusInfo(
          icon: Icons.cloud_done,
          label: 'Uploaded',
          color: Colors.green,
          backgroundColor: Colors.green.withOpacity(0.2),
        );
      case ChunkUploadState.verified:
        return _StatusInfo(
          icon: Icons.verified,
          label: 'Verified',
          color: Colors.teal,
          backgroundColor: Colors.teal.withOpacity(0.2),
        );
      case ChunkUploadState.failed:
        return _StatusInfo(
          icon: Icons.error,
          label: 'Failed',
          color: Colors.red,
          backgroundColor: Colors.red.withOpacity(0.2),
        );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _StatusInfo {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  _StatusInfo({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
  });
}
