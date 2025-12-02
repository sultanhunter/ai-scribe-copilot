import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import 'widgets/uploaded_chunks_list.dart';

class UploadedChunksViewerScreen extends ConsumerWidget {
  final String sessionId;

  const UploadedChunksViewerScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('uploadedChunks'))),
      body: const UploadedChunksList(),
    );
  }
}
