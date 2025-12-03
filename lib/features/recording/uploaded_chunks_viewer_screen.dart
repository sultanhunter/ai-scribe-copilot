import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../providers/service_providers.dart';
import 'widgets/uploaded_chunks_list.dart';

class UploadedChunksViewerScreen extends ConsumerWidget {
  final String sessionId;

  const UploadedChunksViewerScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('uploadedChunks')),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Recording',
            onPressed: () => _shareRecording(context, ref),
          ),
        ],
      ),
      body: const UploadedChunksList(),
    );
  }

  Future<void> _shareRecording(BuildContext context, WidgetRef ref) async {
    // Show loading dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing recording...'),
            ],
          ),
        ),
      );
    }

    try {
      final shareService = ref.read(recordingShareServiceProvider);
      final success = await shareService.shareRecording(sessionId);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (!success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Share cancelled')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: ${e.toString()}')),
        );
      }
    }
  }
}
