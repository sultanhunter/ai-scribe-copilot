import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

// Theme Mode Provider
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.system;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(AppConstants.themeKey);

    if (themeName != null) {
      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.themeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

// Locale Provider
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    _loadLocale();
    return const Locale('en');
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(AppConstants.localeKey);

    if (languageCode != null) {
      state = Locale(languageCode);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.localeKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(() {
  return LocaleNotifier();
});

// User ID Provider
final userIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  String? userId = prefs.getString(AppConstants.userIdKey);

  if (userId == null) {
    // Generate a new user ID for demo purposes
    userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(AppConstants.userIdKey, userId);
  }

  return userId;
});
