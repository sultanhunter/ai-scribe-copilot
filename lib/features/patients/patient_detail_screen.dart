import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/patient.dart';
import '../../models/recording_session.dart';
import '../../providers/service_providers.dart';
import '../../providers/patient_providers.dart';
import '../recording/recording_screen.dart';
import 'widgets/session_card.dart';

final patientSessionsProvider =
    FutureProvider.family<List<RecordingSession>, String>((
      ref,
      patientId,
    ) async {
      final apiService = ref.watch(apiServiceProvider);
      return await apiService.getSessionsByPatient(patientId);
    });

class PatientDetailScreen extends ConsumerWidget {
  final Patient patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final sessionsAsync = ref.watch(patientSessionsProvider(patient.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(patient.name)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildPatientInfoCard(context, loc)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    loc.translate('recordingSessions'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      ref.invalidate(patientSessionsProvider(patient.id));
                    },
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),
          sessionsAsync.when(
            data: (sessions) {
              if (sessions.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_none,
                          size: 64,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          loc.translate('noRecordings'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to start recording',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final session = sessions[index];
                    return SessionCard(
                      session: session,
                      onTap: () {
                        ref
                            .read(selectedPatientProvider.notifier)
                            .select(patient);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RecordingScreen(
                              existingSessionId: session.sessionId,
                            ),
                          ),
                        );
                      },
                    );
                  }, childCount: sessions.length),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loc.translate('networkError'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(error.toString()),
                  ],
                ),
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(selectedPatientProvider.notifier).select(patient);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RecordingScreen()),
          );
        },
        icon: const Icon(Icons.fiber_manual_record),
        label: Text(loc.translate('startRecording')),
      ),
    );
  }

  Widget _buildPatientInfoCard(BuildContext context, AppLocalizations loc) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  patient.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (patient.age != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${loc.translate('age')}: ${patient.age}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (patient.phoneNumber != null || patient.email != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            if (patient.phoneNumber != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(patient.phoneNumber!, style: theme.textTheme.bodyLarge),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (patient.email != null)
              Row(
                children: [
                  Icon(
                    Icons.email_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(patient.email!, style: theme.textTheme.bodyLarge),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
