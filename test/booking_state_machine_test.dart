import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/data/models/booking_state_machine.dart';

void main() {
  group('BookingStateMachine', () {
    test('allows only the canonical forward lifecycle', () {
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.pending,
          BookingStatus.driverAssigned,
        ),
        isTrue,
      );
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.driverAssigned,
          BookingStatus.driverArriving,
        ),
        isTrue,
      );
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.driverArriving,
          BookingStatus.passengerOnBoard,
        ),
        isTrue,
      );
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.passengerOnBoard,
          BookingStatus.paymentConfirmation,
        ),
        isTrue,
      );
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.paymentConfirmation,
          BookingStatus.completed,
        ),
        isTrue,
      );
    });

    test('rejects backward, skipped, and terminal transitions', () {
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.pending,
          BookingStatus.completed,
        ),
        isFalse,
      );
      expect(
        BookingStateMachine.canTransition(
          BookingStatus.completed,
          BookingStatus.pending,
        ),
        isFalse,
      );
      expect(BookingStateMachine.isTerminal(BookingStatus.completed), isTrue);
      expect(BookingStateMachine.isTerminal(BookingStatus.cancelled), isTrue);
    });

    test('history includes completed and cancelled bookings newest first', () {
      final completed = booking(
        id: 'completed',
        status: BookingStatus.completed,
        updatedAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 1, 2),
      );
      final cancelled = booking(
        id: 'cancelled',
        status: BookingStatus.cancelled,
        updatedAt: DateTime(2026, 1, 3),
        cancelledAt: DateTime(2026, 1, 4),
      );
      final pending = booking(
        id: 'pending',
        status: BookingStatus.pending,
        updatedAt: DateTime(2026, 1, 5),
      );

      final history = BookingStateMachine.terminalHistory([
        completed,
        pending,
        cancelled,
      ]);

      expect(history.map((booking) => booking.bookingId), [
        'cancelled',
        'completed',
      ]);
    });

    test('terminal history falls back to updatedAt', () {
      final cancelled = booking(
        id: 'legacy-cancelled',
        status: BookingStatus.cancelled,
        updatedAt: DateTime(2026, 2, 1),
      );

      expect(BookingStateMachine.terminalDate(cancelled), DateTime(2026, 2, 1));
    });
  });
}

Booking booking({
  required String id,
  required BookingStatus status,
  required DateTime updatedAt,
  DateTime? completedAt,
  DateTime? cancelledAt,
}) {
  return Booking(
    bookingId: id,
    passengerId: 'passenger',
    driverId: 'driver',
    pickup: const LatLng(0, 0),
    destination: const LatLng(1, 1),
    pickupAddress: 'Pickup',
    destinationAddress: 'Destination',
    distanceMeters: 1000,
    estimatedFare: 100,
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    status: status,
    createdAt: DateTime(2026),
    updatedAt: updatedAt,
    completedAt: completedAt,
    cancelledAt: cancelledAt,
  );
}
