import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/app_localizations.dart';
import 'providers/app_providers.dart';
import 'providers/service_providers.dart';
import 'features/patients/patients_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final container = ProviderContainer();
  try {
    // Initialize chunk storage service (Hive)
    final storageService = container.read(chunkStorageServiceProvider);
    await storageService.init();

    // Resume any pending uploads from previous session
    final uploadService = container.read(chunkUploadServiceProvider);
    uploadService.startQueueProcessing(); // Start background processing
    await uploadService.resumePendingUploads();

    debugPrint('✅ Services initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing services: $e');
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'AI Scribe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const PatientsScreen(),
    );
  }
}
