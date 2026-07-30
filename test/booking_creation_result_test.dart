import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/data/repositories/booking_repository.dart';

void main() {
  test('booking creation result parses the authoritative callable quote', () {
    final now = DateTime.utc(2026, 7, 29);
    final fallback = Booking(
      bookingId: 'booking-1',
      passengerId: 'passenger-1',
      pickup: const LatLng(10.67, 122.95),
      destination: const LatLng(10.68, 122.96),
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      distanceMeters: 1000,
      estimatedFare: 20,
      additionalPassengers: 0,
      baggageCount: 0,
      isOutsideToda: false,
      status: BookingStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    final result = BookingCreationResult.fromCallable({
      'bookingId': 'booking-1',
      'distanceMeters': 1800,
      'estimatedFare': 47.5,
      'isOutsideToda': true,
      'fareVersion': 7,
      'fareSnapshot': {'version': 7, 'baseFare': 20},
      'authoritativeRoutePolyline': 'encoded-route',
      'searchExpiresAt': '2026-07-29T00:02:00.000Z',
      'fareBreakdown': {
        'baseFare': 20,
        'distanceFare': 10,
        'boundarySurcharge': 17.5,
      },
      'avoidedRouteRestrictionNames': [
        ' Circumferential Road ',
        '',
        'Circumferential Road',
        'Downtown no-service area',
        42,
      ],
    }, fallback: fallback);

    expect(result.distanceMeters, 1800);
    expect(result.estimatedFare, 47.5);
    expect(result.isOutsideToda, isTrue);
    expect(result.fareVersion, 7);
    expect(result.fareSnapshot['baseFare'], 20);
    expect(result.authoritativeRoutePolyline, 'encoded-route');
    expect(result.searchExpiresAt, DateTime.utc(2026, 7, 29, 0, 2));
    expect(result.fareBreakdown['boundarySurcharge'], 17.5);
    expect(result.avoidedRouteRestrictionNames, [
      'Circumferential Road',
      'Downtown no-service area',
    ]);
  });

  test('booking creation result recovers an ambiguous successful retry', () {
    final searchExpiresAt = DateTime.utc(2026, 7, 29, 0, 2);
    final booking = Booking(
      bookingId: 'stable-booking-id',
      passengerId: 'passenger-1',
      pickup: const LatLng(10.67, 122.95),
      destination: const LatLng(10.68, 122.96),
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      distanceMeters: 1800,
      estimatedFare: 47.5,
      authoritativeRoutePolyline: 'server-route',
      fareVersion: 7,
      fareSnapshot: const {'version': 7},
      fareBreakdown: const {'baseFare': 20},
      searchExpiresAt: searchExpiresAt,
      additionalPassengers: 0,
      baggageCount: 0,
      isOutsideToda: true,
      status: BookingStatus.pending,
      createdAt: DateTime.utc(2026, 7, 29),
      updatedAt: DateTime.utc(2026, 7, 29),
    );

    final result = BookingCreationResult.fromBooking(booking);

    expect(result.bookingId, 'stable-booking-id');
    expect(result.authoritativeRoutePolyline, 'server-route');
    expect(result.fareVersion, 7);
    expect(result.fareSnapshot, {'version': 7});
    expect(result.fareBreakdown, {'baseFare': 20});
    expect(result.searchExpiresAt, searchExpiresAt);
  });
}
