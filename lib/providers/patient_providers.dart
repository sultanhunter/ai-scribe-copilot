import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/patient.dart';
import 'app_providers.dart';
import 'service_providers.dart';

// Patients List Provider
final patientsProvider = FutureProvider.autoDispose<List<Patient>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final userId = await ref.watch(userIdProvider.future);

  try {
    return await apiService.getPatients(userId);
  } catch (e) {
    // Return empty list on error for MVP
    return [];
  }
});

// Selected Patient Provider
class SelectedPatientNotifier extends Notifier<Patient?> {
  @override
  Patient? build() => null;

  void select(Patient? patient) {
    state = patient;
  }
}

final selectedPatientProvider =
    NotifierProvider<SelectedPatientNotifier, Patient?>(() {
      return SelectedPatientNotifier();
    });

// Add Patient Provider
final addPatientProvider = FutureProvider.family<Patient, Patient>((
  ref,
  patient,
) async {
  final apiService = ref.watch(apiServiceProvider);
  final userId = await ref.watch(userIdProvider.future);

  return await apiService.addPatient(patient, userId);
});
