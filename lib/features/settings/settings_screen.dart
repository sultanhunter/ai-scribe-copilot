import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_localizations.dart';
import '../../providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: Text(loc.translate('theme')),
                  subtitle: Text(_getThemeName(themeMode, loc)),
                ),
                RadioListTile<ThemeMode>(
                  title: Text(loc.translate('systemTheme')),
                  value: ThemeMode.system,
                  groupValue: themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(themeModeProvider.notifier).setTheme(value);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: Text(loc.translate('light')),
                  value: ThemeMode.light,
                  groupValue: themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(themeModeProvider.notifier).setTheme(value);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: Text(loc.translate('dark')),
                  value: ThemeMode.dark,
                  groupValue: themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(themeModeProvider.notifier).setTheme(value);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(loc.translate('language')),
                  subtitle: Text(_getLanguageName(locale, loc)),
                ),
                RadioListTile<Locale>(
                  title: Text(loc.translate('english')),
                  value: const Locale('en'),
                  groupValue: locale,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(localeProvider.notifier).setLocale(value);
                    }
                  },
                ),
                RadioListTile<Locale>(
                  title: Text(loc.translate('hindi')),
                  value: const Locale('hi'),
                  groupValue: locale,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(localeProvider.notifier).setLocale(value);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getThemeName(ThemeMode mode, AppLocalizations loc) {
    switch (mode) {
      case ThemeMode.system:
        return loc.translate('systemTheme');
      case ThemeMode.light:
        return loc.translate('light');
      case ThemeMode.dark:
        return loc.translate('dark');
    }
  }

  String _getLanguageName(Locale locale, AppLocalizations loc) {
    switch (locale.languageCode) {
      case 'en':
        return loc.translate('english');
      case 'hi':
        return loc.translate('hindi');
      default:
        return locale.languageCode;
    }
  }
}
