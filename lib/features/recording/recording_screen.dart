import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../providers/patient_providers.dart';
import '../../providers/recording_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/app_providers.dart';
import 'widgets/chunk_status_list.dart';
import 'uploaded_chunks_viewer_screen.dart';

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
        // Only reset if not currently recording
        final recordingState = ref.read(recordingSessionProvider);
        if (!recordingState.isRecording) {
          ref.read(recordingSessionProvider.notifier).reset();
        }
        ref
            .read(recordingSessionProvider.notifier)
            .loadExistingSession(widget.existingSessionId!);
      });
    } else {
      // Only reset the session state if not currently recording
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final recordingState = ref.read(recordingSessionProvider);
        if (!recordingState.isRecording) {
          ref.read(recordingSessionProvider.notifier).reset();
        }
      });
    }
  }

  Future<bool> _onWillPop() async {
    final recordingState = ref.read(recordingSessionProvider);

    // If recording is in progress, show a warning dialog
    if (recordingState.isRecording && !recordingState.isPaused) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recording in Progress'),
          content: const Text(
            'Recording is still in progress. Do you want to stop recording and go back?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue Recording'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop & Go Back'),
            ),
          ],
        ),
      );

      if (shouldPop == true) {
        // Stop recording before popping
        await ref.read(recordingSessionProvider.notifier).stopRecording();
        await ref
            .read(recordingSessionProvider.notifier)
            .waitForUploadsToComplete();
      }

      return shouldPop ?? false;
    }

    return true;
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

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(patient.name)),
        body: Column(
          children: [
            // Recording Controls
            SizedBox(
              height: 200,
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
                            recordingState.isRecording &&
                                !recordingState.isPaused
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
                              _formatDuration(recordingState.currentDuration),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Chunk Status List (always shown when session exists)
            if (recordingState.session != null ||
                widget.existingSessionId != null)
              Expanded(
                child: Column(
                  children: [
                    // See uploaded chunks button
                    if (recordingState.session != null &&
                        !recordingState.isRecording &&
                        (recordingState.totalChunks > 0 ||
                            recordingState.session!.totalChunks > 0))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: TextButton.icon(
                          onPressed: () {
                            if (recordingState.session?.sessionId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      UploadedChunksViewerScreen(
                                        sessionId:
                                            recordingState.session!.sessionId,
                                      ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(loc.translate('seeUploadedChunks')),
                        ),
                      ),
                    const Expanded(child: ChunkStatusList()),
                  ],
                ),
              ),
            // Control buttons
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!recordingState.isRecording)
                    ElevatedButton.icon(
                      onPressed: () =>
                          _startOrResumeRecording(context, ref, patient.id),
                      icon: Icon(
                        recordingState.session != null &&
                                recordingState.session!.totalChunks > 0
                            ? Icons.play_arrow
                            : Icons.fiber_manual_record,
                      ),
                      label: Text(
                        recordingState.session != null &&
                                recordingState.session!.totalChunks > 0
                            ? loc.translate('resumeRecording')
                            : loc.translate('startRecording'),
                      ),
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
      ),
    );
  }

  Future<void> _startOrResumeRecording(
    BuildContext context,
    WidgetRef ref,
    String patientId,
  ) async {
    try {
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

      final recordingState = ref.read(recordingSessionProvider);

      // If we have an existing session with any chunks, resume it
      if (recordingState.session != null &&
          recordingState.session!.totalChunks > 0) {
        await ref
            .read(recordingSessionProvider.notifier)
            .resumeRecordingSession();
      } else {
        // Otherwise start a new recording
        final userId = await ref.read(userIdProvider.future);
        await ref
            .read(recordingSessionProvider.notifier)
            .startRecording(patientId, userId);
      }
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
    // Show uploading dialog immediately
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

    // Stop recording
    await ref.read(recordingSessionProvider.notifier).stopRecording();

    // Wait for pending uploads
    await ref
        .read(recordingSessionProvider.notifier)
        .waitForUploadsToComplete();

    // Force refresh the chunk storage to update UI with latest states
    final sessionId = ref.read(recordingSessionProvider).session?.sessionId;
    if (sessionId != null) {
      // Invalidate the provider to force rebuild with updated chunk states
      ref.invalidate(currentSessionChunksProvider);
    }

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
