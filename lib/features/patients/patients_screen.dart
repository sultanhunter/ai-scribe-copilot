import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/patient.dart';
import '../../providers/patient_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/app_providers.dart';
import '../recording/recording_screen.dart';
import '../settings/settings_screen.dart';

class PatientsScreen extends ConsumerWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientsAsync = ref.watch(patientsProvider);
    final loc = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('patients')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: patientsAsync.when(
        data: (patients) {
          if (patients.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.translate('noPatients'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(patient.name.substring(0, 1).toUpperCase()),
                  ),
                  title: Text(patient.name),
                  subtitle: Text(
                    patient.phoneNumber ??
                        loc.translate('patientId') + ': ${patient.id}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ref.read(selectedPatientProvider.notifier).select(patient);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecordingScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                loc.translate('networkError'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(error.toString()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddPatientDialog(context, ref),
        icon: const Icon(Icons.add),
        label: Text(loc.translate('addPatient')),
      ),
    );
  }

  void _showAddPatientDialog(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final ageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.translate('addPatient')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: loc.translate('patientName'),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: loc.translate('phoneNumber'),
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: loc.translate('email'),
                  prefixIcon: const Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ageController,
                decoration: InputDecoration(
                  labelText: loc.translate('age'),
                  prefixIcon: const Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;

              final patient = Patient(
                id: const Uuid().v4(),
                name: nameController.text,
                phoneNumber: phoneController.text.isEmpty
                    ? null
                    : phoneController.text,
                email: emailController.text.isEmpty
                    ? null
                    : emailController.text,
                age: ageController.text.isEmpty
                    ? null
                    : int.tryParse(ageController.text),
              );

              try {
                final userId = await ref.read(userIdProvider.future);
                final apiService = ref.read(apiServiceProvider);
                await apiService.addPatient(patient, userId);

                // Refresh patients list
                ref.invalidate(patientsProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(loc.translate('networkError'))),
                  );
                }
              }
            },
            child: Text(loc.translate('save')),
          ),
        ],
      ),
    );
  }
}
