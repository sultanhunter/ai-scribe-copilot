import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../providers/patient_providers.dart';
import '../../providers/recording_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/app_providers.dart';
import 'widgets/chunk_status_list.dart';
import 'widgets/uploaded_chunks_list.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  final String? existingSessionId;

  const RecordingScreen({super.key, this.existingSessionId});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  @override
  void initState() {
    super.initState();
    // If viewing an existing session, load it
    if (widget.existingSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(recordingSessionProvider.notifier).reset();
        ref
            .read(recordingSessionProvider.notifier)
            .loadExistingSession(widget.existingSessionId!);
      });
    } else {
      // Reset the session state for a new recording
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(recordingSessionProvider.notifier).reset();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final patient = ref.watch(selectedPatientProvider);
    final recordingState = ref.watch(recordingSessionProvider);

    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.translate('recording'))),
        body: Center(child: Text(loc.translate('selectPatient'))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(patient.name)),
      body: Column(
        children: [
          // Recording Controls
          SizedBox(
            height: 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Audio level visualization
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          recordingState.isRecording && !recordingState.isPaused
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.2),
                      border: Border.all(
                        color:
                            recordingState.isRecording &&
                                !recordingState.isPaused
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            recordingState.isRecording &&
                                    !recordingState.isPaused
                                ? Icons.mic
                                : Icons.mic_off,
                            size: 48,
                            color:
                                recordingState.isRecording &&
                                    !recordingState.isPaused
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _formatDuration(recordingState.duration),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (recordingState.isRecording) ...[
                    // Audio level indicator
                    Container(
                      width: 150,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: recordingState.currentAmplitude.clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (recordingState.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        recordingState.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Chunk Status List (shown while recording)
          if (recordingState.isRecording)
            const Expanded(child: ChunkStatusList())
          // Uploaded Chunks List (shown when not recording or viewing existing session)
          else if (recordingState.session != null ||
              widget.existingSessionId != null)
            const Expanded(child: UploadedChunksList()),
          // Control buttons
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!recordingState.isRecording)
                  ElevatedButton.icon(
                    onPressed: () => _startRecording(context, ref, patient.id),
                    icon: const Icon(Icons.fiber_manual_record),
                    label: Text(loc.translate('startRecording')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  )
                else ...[
                  if (!recordingState.isPaused)
                    IconButton.filled(
                      onPressed: () => ref
                          .read(recordingSessionProvider.notifier)
                          .pauseRecording(),
                      icon: const Icon(Icons.pause),
                      iconSize: 32,
                    )
                  else
                    IconButton.filled(
                      onPressed: () => ref
                          .read(recordingSessionProvider.notifier)
                          .resumeRecording(),
                      icon: const Icon(Icons.play_arrow),
                      iconSize: 32,
                    ),
                  const SizedBox(width: 24),
                  IconButton.filled(
                    onPressed: () => _stopRecording(context, ref),
                    icon: const Icon(Icons.stop),
                    iconSize: 32,
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording(
    BuildContext context,
    WidgetRef ref,
    String patientId,
  ) async {
    try {
      final userId = await ref.read(userIdProvider.future);

      // Check permissions
      final audioService = ref.read(audioRecordingServiceProvider);
      if (!await audioService.checkPermissions()) {
        final granted = await audioService.requestPermissions();
        if (!granted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).translate('permissionDenied'),
                ),
              ),
            );
          }
          return;
        }
      }

      await ref
          .read(recordingSessionProvider.notifier)
          .startRecording(patientId, userId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).translate('networkError'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _stopRecording(BuildContext context, WidgetRef ref) async {
    await ref.read(recordingSessionProvider.notifier).stopRecording();

    // Wait for pending uploads
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Uploading remaining chunks...'),
            ],
          ),
        ),
      );
    }

    await ref
        .read(recordingSessionProvider.notifier)
        .waitForUploadsToComplete();

    if (context.mounted) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording saved successfully!')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}
