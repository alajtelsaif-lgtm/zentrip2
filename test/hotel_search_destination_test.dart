import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/hotel_booking/logic/hotel_controller.dart';
import 'package:zentrip/features/hotel_booking/presentation/screens/hotel_search_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/hotel_destination_suggestion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HotelDestinationSuggestion destination(
    String name, {
    String? localizedName,
  }) =>
      HotelDestinationSuggestion(
        name: name,
        localizedName: localizedName,
        countryName: 'United Arab Emirates',
        countryNameLocalized: 'الإمارات العربية المتحدة',
        latitude: 25.2048,
        longitude: 55.2708,
      );

  test('debounces destination requests and ignores stale responses', () async {
    final firstResponse = Completer<List<HotelDestinationSuggestion>>();
    final requestedQueries = <String>[];
    final controller = HotelController(
      loadDestinations: (query) {
        requestedQueries.add(query);
        if (query == 'lo') return firstResponse.future;
        return Future.value([destination('Paris')]);
      },
    );

    controller.updateDestinationQuery('l');
    controller.updateDestinationQuery('lo');
    await Future<void>.delayed(const Duration(milliseconds: 390));
    expect(requestedQueries, ['lo']);

    controller.updateDestinationQuery(
      'par',
      debounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    firstResponse.complete([destination('London')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.destinationSuggestions.single.name, 'Paris');
    controller.dispose();
  });

  test('uses English and Arabic plural forms for stay counts', () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final arabic = await AppLocalizations.delegate.load(const Locale('ar'));

    expect(english.hotelNightsSummary(1), '1 night');
    expect(english.hotelRoomsSummary(2), '2 rooms');
    expect(english.hotelGuestsSummary(1), '1 guest');
    expect(arabic.hotelNightsSummary(2), 'ليلتان');
    expect(arabic.hotelNightsSummary(3), '3 ليالٍ');
    expect(arabic.hotelNightsSummary(11), '11 ليلة');
    expect(arabic.hotelRoomsSummary(2), 'غرفتان');
    expect(arabic.hotelRoomsSummary(11), '11 غرفة');
    expect(arabic.hotelGuestsSummary(2), 'ضيفان');
    expect(arabic.hotelGuestsSummary(11), '11 ضيف');
  });

  test('popular fallback matches Latin and Arabic destination prefixes', () {
    expect(
      HotelDestinationSuggestion.popularMatches('lo')
          .any((place) => place.name == 'London'),
      isTrue,
    );
    expect(
      HotelDestinationSuggestion.popularMatches('par')
          .any((place) => place.name == 'Paris'),
      isTrue,
    );
    expect(
      HotelDestinationSuggestion.popularMatches('دب')
          .any((place) => place.name == 'Dubai'),
      isTrue,
    );
    expect(
      HotelDestinationSuggestion.popularMatches('القا')
          .any((place) => place.name == 'Cairo'),
      isTrue,
    );
  });

  testWidgets('selects an English destination suggestion', (tester) async {
    final controller = HotelController(
      loadDestinations: (_) async =>
          [destination('Dubai', localizedName: 'دبي')],
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HotelSearchScreen(controller: controller),
    ));

    final destinationField = find.byType(TextField).first;
    await tester.enterText(destinationField, 'du');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Dubai'), findsOneWidget);

    await tester.tap(find.text('Dubai'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(destinationField).controller!.text, 'Dubai');
    controller.dispose();
  });

  testWidgets('renders Arabic destination names in an RTL locale',
      (tester) async {
    final controller = HotelController(
      loadDestinations: (_) async =>
          [destination('Dubai', localizedName: 'دبي')],
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HotelSearchScreen(controller: controller),
    ));

    final destinationField = find.byType(TextField).first;
    await tester.enterText(destinationField, 'دب');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('دبي'), findsOneWidget);

    await tester.tap(find.text('دبي'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(destinationField).controller!.text, 'دبي');
    controller.dispose();
  });
}
