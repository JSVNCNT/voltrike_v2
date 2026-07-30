import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/calls/call_participant_identity.dart';

void main() {
  final booking = Booking.fromMap(
    bookingId: 'booking-1',
    data: {
      'passengerId': 'passenger-1',
      'passengerName': 'Maria Santos',
      'passengerPhotoUrl': 'https://example.com/passenger.jpg',
      'driverId': 'driver-1',
      'driverName': 'Juan Dela Cruz',
      'driverPhotoUrl': 'https://example.com/driver.jpg',
      'status': 'driverAssigned',
    },
  );

  test('passenger call UI displays the assigned driver', () {
    final identity = CallParticipantIdentity.fromBooking(
      booking: booking,
      currentUserId: 'passenger-1',
    );

    expect(identity.name, 'Juan Dela Cruz');
    expect(identity.roleLabel, 'Your driver');
    expect(identity.photoUrl, 'https://example.com/driver.jpg');
    expect(identity.initials, 'JC');
  });

  test('driver call UI displays the current passenger', () {
    final identity = CallParticipantIdentity.fromBooking(
      booking: booking,
      currentUserId: 'driver-1',
    );

    expect(identity.name, 'Maria Santos');
    expect(identity.roleLabel, 'Your passenger');
    expect(identity.photoUrl, 'https://example.com/passenger.jpg');
    expect(identity.initials, 'MS');
  });

  test('identity falls back safely when the booking member is unknown', () {
    final identity = CallParticipantIdentity.fromBooking(
      booking: booking,
      currentUserId: null,
    );

    expect(identity.name, 'Ride participant');
    expect(identity.roleLabel, 'Your current ride');
    expect(identity.initials, 'RP');
  });
}
