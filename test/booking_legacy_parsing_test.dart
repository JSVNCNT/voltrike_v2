import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking.dart';

void main() {
  test('legacy booking fields parse without throwing', () {
    final booking = Booking.fromMap(
      bookingId: 'legacy-booking',
      data: {
        'passengerId': 'passenger-1',
        'pickupLatitude': 10.67,
        'pickupLongitude': 122.95,
        'destinationLatitude': 10.68,
        'destinationLongitude': 122.96,
        'pickupName': 'Legacy Pickup',
        'dropoffAddress': 'Legacy Destination',
        'distanceMeters': '1250',
        'estimatedFare': 45,
        'status': 'unknown-legacy-status',
      },
    );

    expect(booking.schemaVersion, 0);
    expect(booking.passengerId, 'passenger-1');
    expect(booking.pickupAddress, 'Legacy Pickup');
    expect(booking.destinationAddress, 'Legacy Destination');
    expect(booking.distanceMeters, 1250);
    expect(booking.status, BookingStatus.pending);
    expect(booking.additionalPassengers, 0);
    expect(booking.baggageCount, 0);
  });

  test('current serialization always writes the current schema version', () {
    final booking = Booking.fromMap(
      bookingId: 'booking-1',
      data: const <String, dynamic>{},
    );

    expect(
      booking.toFirestore()['schemaVersion'],
      Booking.currentSchemaVersion,
    );
  });
}
