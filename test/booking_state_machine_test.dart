import 'package:flutter_test/flutter_test.dart';
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
  });
}
