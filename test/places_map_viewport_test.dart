import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/nearby/presentation/screens/places_map_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/attraction_map_viewport.dart';
import 'package:zentrip/models/map_search_result.dart';

void main() {
  testWidgets('loads attractions for the selected place viewport',
      (tester) async {
    final requests = <Map<String, Object?>>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlacesMapScreen(
          selectedPlace: const MapSearchResult(
            title: 'Leptis Magna',
            address: 'Khoms, Libya',
            category: 'historical',
            placeId: 'P0001',
            latitude: 32.638,
            longitude: 14.293,
          ),
          loadAttractionViewport: ({
            required double south,
            required double west,
            required double north,
            required double east,
            required double zoom,
            String? category,
            int minRate = 0,
            String? language,
          }) async {
            requests.add({
              'south': south,
              'west': west,
              'north': north,
              'east': east,
              'zoom': zoom,
              'language': language,
            });
            return const AttractionMapViewport(attractions: []);
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Places Map'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single['south'], isA<double>());
    expect(requests.single['north'], isA<double>());
    expect(requests.single['language'], 'en');
  });
}
