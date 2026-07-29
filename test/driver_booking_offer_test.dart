import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/driver_booking_offer.dart';

void main() {
  final expiresAt = DateTime.utc(2026, 8, 1);

  DriverBookingOffer offer({
    required String bookingId,
    required DateTime queueEnteredAt,
    int servicePriority = 0,
    int distanceMeters = 0,
    String? stableId,
  }) {
    return DriverBookingOffer(
      bookingId: bookingId,
      expiresAt: expiresAt,
      queueEnteredAt: queueEnteredAt,
      servicePriority: servicePriority,
      distanceMeters: distanceMeters,
      stableId: stableId ?? bookingId,
    );
  }

  test(
    'parses authoritative dispatch ordering fields and timestamp fallback',
    () {
      final bookingCreatedAt = DateTime.utc(2026, 7, 30, 9);
      final createdAt = DateTime.utc(2026, 7, 30, 10);
      final parsed = DriverBookingOffer.fromMap(
        documentId: 'document-id',
        data: <String, Object?>{
          'bookingId': 'booking-id',
          'offerId': 'offer-id',
          'expiresAt': expiresAt,
          'distanceMeters': 1450.4,
          'servicePriority': 1,
          'bookingCreatedAt': bookingCreatedAt.toIso8601String(),
          'createdAt': createdAt.millisecondsSinceEpoch,
        },
      );

      expect(parsed.bookingId, 'booking-id');
      expect(parsed.stableId, 'offer-id');
      expect(parsed.distanceMeters, 1450);
      expect(parsed.servicePriority, 1);
      expect(parsed.bookingCreatedAt, bookingCreatedAt);
      expect(parsed.createdAt, createdAt);
      expect(parsed.effectiveQueueTime, bookingCreatedAt);
    },
  );

  test('queueEnteredAt takes precedence over later fallback timestamps', () {
    final queueEnteredAt = DateTime.utc(2026, 7, 30, 8);
    final parsed = DriverBookingOffer.fromMap(
      documentId: 'booking-id',
      data: <String, Object?>{
        'expiresAt': expiresAt,
        'queueEnteredAt': queueEnteredAt,
        'bookingCreatedAt': DateTime.utc(2026, 7, 30, 9),
        'createdAt': DateTime.utc(2026, 7, 30, 10),
      },
    );

    expect(parsed.effectiveQueueTime, queueEnteredAt);
  });

  test('sorts oldest queue first before service priority or distance', () {
    final olderFarther = offer(
      bookingId: 'older-farther',
      queueEnteredAt: DateTime.utc(2026, 7, 30, 8),
      servicePriority: 2,
      distanceMeters: 5000,
    );
    final newerCloser = offer(
      bookingId: 'newer-closer',
      queueEnteredAt: DateTime.utc(2026, 7, 30, 9),
      servicePriority: 0,
      distanceMeters: 100,
    );
    final offers = <DriverBookingOffer>[newerCloser, olderFarther]
      ..sort(DriverBookingOffer.compareForDisplay);

    expect(offers.map((item) => item.bookingId), <String>[
      'older-farther',
      'newer-closer',
    ]);
  });

  test('uses service priority, distance, then stable ID as tie-breakers', () {
    final enteredAt = DateTime.utc(2026, 7, 30, 8);
    final offers = <DriverBookingOffer>[
      offer(
        bookingId: 'priority-one-far',
        queueEnteredAt: enteredAt,
        servicePriority: 1,
        distanceMeters: 1000,
      ),
      offer(
        bookingId: 'priority-zero-far',
        queueEnteredAt: enteredAt,
        distanceMeters: 2000,
      ),
      offer(
        bookingId: 'stable-b',
        queueEnteredAt: enteredAt,
        distanceMeters: 1000,
        stableId: 'b',
      ),
      offer(
        bookingId: 'stable-a',
        queueEnteredAt: enteredAt,
        distanceMeters: 1000,
        stableId: 'a',
      ),
    ]..sort(DriverBookingOffer.compareForDisplay);

    expect(offers.map((item) => item.bookingId), <String>[
      'stable-a',
      'stable-b',
      'priority-zero-far',
      'priority-one-far',
    ]);
  });
}
