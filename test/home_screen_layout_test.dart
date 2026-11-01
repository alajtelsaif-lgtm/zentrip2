import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/core/services/current_location_service.dart';
import 'package:zentrip/features/home/presentation/screens/home_screen.dart';
import 'package:zentrip/features/transfers/presentation/screens/transfers_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  ApiService.instance.init();

  testWidgets('home destinations swap and the offers section is scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(locationService: _UnavailableLocationService()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('MRA').first, findsOneWidget);
    expect(find.text('MJI').first, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('MRA').first).dy,
      lessThan(tester.getTopLeft(find.text('MJI').first).dy),
    );

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('MJI').first).dy,
      lessThan(tester.getTopLeft(find.text('MRA').first).dy),
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));
    expect(find.text(l10n.popular), findsNothing);
    expect(find.text('Indonesia AirAsia'), findsNothing);
    expect(find.text(l10n.homeMonuments), findsOneWidget);
    final offersHeader = find.text(l10n.homeOffers);
    await tester.ensureVisible(offersHeader);
    await tester.pump();
    expect(offersHeader, findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets(
      'home flight card edits airports, trip type, passengers and class',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(locationService: _UnavailableLocationService()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));

    await tester.tap(find.text('MRA').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MRA');
    await tester.pump();
    await tester.tap(find.text('Misrata · Libya [MRA]'));
    await tester.pumpAndSettle();
    expect(find.text('MRA').first, findsOneWidget);

    await tester.tap(find.text(l10n.oneWay));
    await tester.pump();
    expect(find.text('—'), findsOneWidget);

    await tester.tap(find.text(l10n.passengers).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.tap(find.text(
      MaterialLocalizations.of(tester.element(find.byType(HomeScreen)))
          .okButtonLabel,
    ));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text(l10n.travelClass));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.business));
    await tester.pumpAndSettle();
    expect(find.text(l10n.business), findsOneWidget);
  });

  testWidgets('home hotel, car, and transfer actions open existing searches',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    RouteSettings? lastRoute;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(locationService: _UnavailableLocationService()),
        onGenerateRoute: (settings) {
          lastRoute = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return'),
              ),
            ),
          );
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)));

    await tester.ensureVisible(find.text(l10n.quickActionHotels));
    await tester.tap(find.text(l10n.quickActionHotels));
    await tester.pumpAndSettle();
    expect(lastRoute?.name, AppRoutes.hotelSearch);
    expect(lastRoute?.arguments, isNull);

    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.quickActionCars));
    await tester.tap(find.text(l10n.quickActionCars));
    await tester.pumpAndSettle();
    expect(lastRoute?.name, AppRoutes.carRental);
    expect(lastRoute?.arguments, isNull);

    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.quickActionTransfers));
    await tester.tap(find.text(l10n.quickActionTransfers));
    await tester.pumpAndSettle();
    expect(lastRoute?.name, AppRoutes.transfers);
    final transferArgs = lastRoute?.arguments as TransferSearchRouteArgs;
    expect(transferArgs.initialFromLocation, 'Misrata');
    expect(transferArgs.initialToLocation, 'Tripoli');
  });
}

class _UnavailableLocationService extends CurrentLocationService {
  const _UnavailableLocationService();

  @override
  Future<Position> getPosition() async {
    throw const CurrentLocationException(CurrentLocationError.permissionDenied);
  }
}
