import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_theme.dart';
import 'core/services/api_service.dart';
import 'core/services/currency_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/push_notification_service.dart';
import 'features/favorites/logic/favorites_controller.dart';
import 'features/notifications/logic/notifications_store.dart';
import 'features/price_alerts/logic/price_alerts_store.dart';
import 'global_widgets/app_snackbar.dart';
import 'global_widgets/locale_controller.dart';
import 'global_widgets/theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'routes/app_routes.dart';

/// مفتاح تنقّل عام يسمح بالتنقل من أي مكان في التطبيق حتى خارج BuildContext.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.instance.init();

  // عند أي رد 401 من الخادم: امسح الجلسة وأعد التوجيه لشاشة الدخول فوراً.
  ApiService.instance.onSessionExpired = () {
    final context = navigatorKey.currentContext;
    if (context != null) {
      AppSnackbar.warning(
        context,
        AppLocalizations.of(context).sessionExpiredMessage,
      );
    }
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.auth,
      (r) => false,
    );
  };

  runApp(const ZentripApp());
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  await Future.wait([
    _initializeSafely('theme', ThemeController.instance.loadSavedTheme),
    _initializeSafely('locale', LocaleController.instance.loadSavedLocale),
    _initializeSafely('favorites', FavoritesController.instance.load),
    _initializeSafely('notifications', NotificationsStore.instance.load),
    _initializeSafely('price alerts', PriceAlertsStore.instance.load),
    _initializeSafely('currency', CurrencyService.instance.init),
    _initializeSafely('connectivity', ConnectivityService.instance.init),
    _initializeSafely(
        'push notifications', PushNotificationService.instance.initialize),
  ]);
}

Future<void> _initializeSafely(
  String service,
  Future<void> Function() initialize,
) async {
  try {
    await initialize().timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('Startup initialization for $service was skipped: $error');
  }
}

class ZentripApp extends StatelessWidget {
  const ZentripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ThemeController.instance,
        LocaleController.instance,
      ]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          initialRoute: AppRoutes.splash,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          locale: LocaleController.instance.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: (locale, supportedLocales) =>
              LocaleController.resolveSupportedLocale(locale, supportedLocales),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
