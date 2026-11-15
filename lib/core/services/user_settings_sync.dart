import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../global_widgets/locale_controller.dart';
import '../../global_widgets/theme_controller.dart';
import 'api_service.dart';
import 'currency_service.dart';

/// Keeps a signed-in customer's app settings (notification toggles,
/// language, currency, theme) in the database so they follow the account
/// to other devices. The device copy in SharedPreferences stays as the
/// offline cache and is what the app reads at startup.
class UserSettingsSync {
  static final UserSettingsSync instance = UserSettingsSync._();
  UserSettingsSync._();

  static const notificationKeys = [
    'notif_trip',
    'notif_promo',
    'notif_zen',
    'notif_general',
  ];

  bool _applying = false;

  /// Sends changed settings to the server. Failures are logged only; the
  /// setting is already saved on the device.
  Future<void> push(Map<String, Object> changes) async {
    if (_applying || changes.isEmpty) return;
    final api = ApiService.instance;
    if (!api.canSyncSavedData) return;
    final result = await api.saveUserSettings(changes);
    if (result.isFailure) {
      debugPrint('Settings were kept on this device only: ${result.errorMessage}');
    }
  }

  /// Loads the account's saved settings and applies them on this device.
  /// The first time an account syncs and has nothing stored yet, the
  /// current device settings are uploaded instead.
  Future<void> pullAndApply() async {
    final api = ApiService.instance;
    if (!api.canSyncSavedData) return;
    final result = await api.getUserSettings();
    if (!result.isSuccess || result.data == null) return;
    final settings = result.data!;
    if (settings.isEmpty) {
      await push(await _currentDeviceSettings());
      return;
    }
    _applying = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in notificationKeys) {
        final value = settings[key];
        if (value is bool) await prefs.setBool(key, value);
      }
      final locale = settings['locale'];
      if (locale is String && locale.isNotEmpty) {
        await LocaleController.instance.setLocale(Locale(locale));
      }
      final currency = settings['currency'];
      if (currency is String && currency.isNotEmpty) {
        try {
          await CurrencyService.instance.selectCode(currency);
        } on ArgumentError {
          debugPrint('Ignoring unsupported saved currency $currency');
        }
      }
      final theme = settings['theme'];
      if (theme is String) {
        final mode = switch (theme) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
        await ThemeController.instance.setTheme(mode);
      }
    } finally {
      _applying = false;
    }
  }

  Future<Map<String, Object>> _currentDeviceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object>{
      'locale': LocaleController.instance.locale.languageCode,
      'currency': CurrencyService.instance.selected.code,
      'theme': themeName(ThemeController.instance.themeMode),
    };
    for (final key in notificationKeys) {
      final value = prefs.getBool(key);
      if (value != null) values[key] = value;
    }
    return values;
  }

  static String themeName(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      };
}
