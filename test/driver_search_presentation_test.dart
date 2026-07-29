import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/passenger/presentation/models/driver_search_presentation.dart';

void main() {
  group('DriverSearchPresentation countdown', () {
    final createdAt = DateTime.utc(2026, 7, 29, 10);

    test('uses the booking creation time and never exceeds the timeout', () {
      expect(
        DriverSearchPresentation.remainingSeconds(
          bookingCreatedAt: createdAt,
          now: createdAt.subtract(const Duration(seconds: 5)),
        ),
        60,
      );
      expect(
        DriverSearchPresentation.remainingSeconds(
          bookingCreatedAt: createdAt,
          now: createdAt.add(const Duration(milliseconds: 1500)),
        ),
        59,
      );
    });

    test('reaches zero when the search deadline expires', () {
      expect(
        DriverSearchPresentation.remainingSeconds(
          bookingCreatedAt: createdAt,
          now: createdAt.add(const Duration(seconds: 60)),
        ),
        0,
      );
      expect(
        DriverSearchPresentation.remainingSeconds(
          bookingCreatedAt: createdAt,
          now: createdAt.add(const Duration(minutes: 5)),
        ),
        0,
      );
    });

    test('formats a stable timer label', () {
      expect(DriverSearchPresentation.formatCountdown(60), '1:00');
      expect(DriverSearchPresentation.formatCountdown(9), '0:09');
      expect(DriverSearchPresentation.formatCountdown(-1), '0:00');
    });
  });

  group('DriverSearchPresentation availability copy', () {
    test('requests high-capacity tuktuks for three or more riders', () {
      expect(DriverSearchPresentation.requiresHighCapacity(1), isFalse);
      expect(DriverSearchPresentation.requiresHighCapacity(2), isTrue);
      expect(
        DriverSearchPresentation.searchingMessage(additionalPassengers: 2),
        contains('high-capacity electric tuktuk'),
      );
    });

    test('always gives No drivers available a contextual explanation', () {
      expect(
        DriverSearchPresentation.unavailableMessage(
          additionalPassengers: 2,
          isOutsideToda: false,
        ),
        'No high-capacity electric tuktuks are available right now.',
      );
      expect(
        DriverSearchPresentation.unavailableMessage(
          additionalPassengers: 0,
          isOutsideToda: true,
        ),
        'No tuktuks are serving this area right now.',
      );
      expect(
        DriverSearchPresentation.unavailableMessage(
          additionalPassengers: 0,
          isOutsideToda: false,
        ),
        'No nearby drivers are available right now.',
      );
    });
  });
}
