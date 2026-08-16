import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/data/models/booking.dart';

void main() {
  test('legacy booking fields parse when lifecycle status is supported', () {
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
        'status': 'pending',
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
    expect(
      booking.createdAt,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  });

  test(
    'unsupported lifecycle status is rejected instead of becoming pending',
    () {
      expect(
        () => Booking.fromMap(
          bookingId: 'corrupt-booking',
          data: const <String, dynamic>{
            'passengerId': 'passenger-1',
            'status': 'unknown-legacy-status',
          },
        ),
        throwsFormatException,
      );
    },
  );

  test('legacy completed rides preserve gross as driver net earnings', () {
    final booking = Booking.fromMap(
      bookingId: 'legacy-completed',
      data: const <String, dynamic>{
        'passengerId': 'passenger-1',
        'estimatedFare': 75,
        'amountDue': 80,
        'status': 'completed',
      },
    );

    expect(booking.grossFare, 80);
    expect(booking.commissionAmount, 0);
    expect(booking.driverNetEarnings, 80);
  });

  test('current settlement and quote snapshots parse without drift', () {
    final booking = Booking.fromMap(
      bookingId: 'current-booking',
      data: {
        'passengerId': 'passenger-1',
        'estimatedFare': 100,
        'amountDue': 100,
        'grossFare': 100,
        'commissionPercent': 7.5,
        'commissionAmount': 7.5,
        'driverNetEarnings': 92.5,
        'fareSnapshot': {'version': 4},
        'fareBreakdown': {'total': 100},
        'authoritativeRoutePolyline': 'abc',
        'searchExpiresAt': '2026-07-30T01:00:00.000Z',
        'status': 'completed',
      },
    );

    expect(booking.fareVersion, 4);
    expect(booking.fareBreakdown['total'], 100);
    expect(booking.authoritativeRoutePolyline, 'abc');
    expect(booking.searchExpiresAt, DateTime.utc(2026, 7, 30, 1));
    expect(booking.driverNetEarnings, 92.5);
  });

  test('current serialization always writes the current schema version', () {
    final booking = Booking.fromMap(
      bookingId: 'booking-1',
      data: const <String, dynamic>{'status': 'pending'},
    );

    expect(
      booking.toFirestore()['schemaVersion'],
      Booking.currentSchemaVersion,
    );
  });

  test('current schema rejects missing coordinates and timestamps', () {
    expect(
      () => Booking.fromMap(
        bookingId: 'invalid-current-booking',
        data: const <String, dynamic>{
          'schemaVersion': Booking.currentSchemaVersion,
          'status': 'pending',
        },
      ),
      throwsFormatException,
    );
  });

  test('multi-stop booking exposes ordered active destinations', () {
    final booking = Booking.fromMap(
      bookingId: 'multi-stop',
      data: {
        'passengerId': 'passenger-1',
        'status': 'passengerOnBoard',
        'destination': {'latitude': 10.69, 'longitude': 122.97},
        'destinationAddress': 'Final stop',
        'dropoffCount': 2,
        'activeStopIndex': 1,
        'passengerNote': 'Blue gate',
        'routeStops': [
          {
            'sequence': 0,
            'type': 'pickup',
            'location': {'latitude': 10.67, 'longitude': 122.95},
            'name': 'Pickup',
            'address': 'Pickup',
          },
          {
            'sequence': 1,
            'type': 'dropoff',
            'location': {'latitude': 10.68, 'longitude': 122.96},
            'name': 'First stop',
            'address': 'First stop',
            'final': false,
          },
          {
            'sequence': 2,
            'type': 'dropoff',
            'location': {'latitude': 10.69, 'longitude': 122.97},
            'name': 'Final stop',
            'address': 'Final stop',
            'final': true,
          },
        ],
      },
    );
    expect(booking.hasMultipleDropoffs, isTrue);
    expect(booking.activeDestinationStop.name, 'First stop');
    expect(booking.orderedDropoffLabel, 'First stop → Final stop');
    expect(booking.passengerNote, 'Blue gate');
  });

  test('route-stop command payload excludes server projection fields', () {
    final stop = BookingRouteStop(
      sequence: 1,
      type: 'dropoff',
      location: const LatLng(10.68, 122.96),
      name: 'First stop',
      address: 'First stop address',
      status: 'completed',
      completedAt: DateTime.utc(2026, 8, 17),
    );

    final command = stop.toCommandMap();
    expect(command['sequence'], 1);
    expect(command['type'], 'dropoff');
    expect(command, isNot(contains('status')));
    expect(command, isNot(contains('completedAt')));
  });
}
