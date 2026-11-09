import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/features/chatbot/logic/chatbot_controller.dart';

void main() {
  group('Zen AI itinerary parsing', () {
    test('parses English day headings, activities, destination and budget', () {
      final itinerary = ChatbotController.parseItineraryResponse(
        '''
        Day 1 | Old Town
        • Visit the historic square
        - Try local food

        Day 2 | Coast
        • Walk along the beach
        Estimated budget: \$250 per person
        ''',
        requestedDestination: 'Plan a trip to Tripoli for 2 days',
      );

      expect(itinerary?['destination'], 'Tripoli');
      expect(itinerary?['estimated_budget'], '\$250 per person');
      expect(itinerary?['days'], [
        {
          'title': 'Day 1 | Old Town',
          'activities': ['Visit the historic square', 'Try local food'],
        },
        {
          'title': 'Day 2 | Coast',
          'activities': ['Walk along the beach'],
        },
      ]);
    });

    test('parses Arabic day headings and destination', () {
      final itinerary = ChatbotController.parseItineraryResponse(
        '''
        **اليوم ١ | المدينة القديمة**
        • زيارة المدينة القديمة
        اليوم ٢: الساحل
        - المشي على الشاطئ
        ''',
        requestedDestination: 'أريد برنامج سفر إلى طرابلس لمدة يومين',
      );

      expect(itinerary?['destination'], 'طرابلس');
      expect(itinerary?['days'], [
        {
          'title': 'اليوم ١ | المدينة القديمة',
          'activities': ['زيارة المدينة القديمة'],
        },
        {
          'title': 'اليوم ٢ | الساحل',
          'activities': ['المشي على الشاطئ'],
        },
      ]);
    });

    test('does not make an itinerary card from unstructured text', () {
      expect(
        ChatbotController.parseItineraryResponse(
          'I can help you plan a trip. What dates are you considering?',
        ),
        isNull,
      );
    });
  });

  group('Zen AI itinerary saving', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saves itinerary state into the existing local chat history',
        () async {
      final controller = ChatbotController();
      addTearDown(controller.dispose);
      final now = DateTime.utc(2026, 1, 1);
      final itineraryMessage = ChatMessage(
        text: 'Day 1 | Tripoli\n• Visit the old city',
        isUser: false,
        timestamp: now,
        isItinerary: true,
        itineraryData: {
          'destination': 'Tripoli',
          'days': [
            {
              'title': 'Day 1 | Tripoli',
              'activities': ['Visit the old city'],
            },
          ],
        },
      );
      controller.messages
        ..add(
          ChatMessage(
            text: 'Plan a trip to Tripoli',
            isUser: true,
            timestamp: now,
          ),
        )
        ..add(itineraryMessage);

      await controller.saveItinerary(itineraryMessage);

      final savedInMemory = controller.messages.last;
      expect(savedInMemory.isSavedItinerary, isTrue);
      expect(savedInMemory.itineraryData?['destination'], 'Tripoli');

      final sessions = await ChatbotController.loadHistory();
      expect(sessions, hasLength(1));
      expect(sessions.single.messages.last.isSavedItinerary, isTrue);
      expect(
        sessions.single.messages.last.itineraryData?['destination'],
        'Tripoli',
      );
    });
  });
}
