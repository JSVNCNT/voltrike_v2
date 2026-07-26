import 'booking.dart';

/// The single durable booking-state contract shared by repositories, UI
/// action policies, backend payloads, and tests.
class BookingStateMachine {
  const BookingStateMachine._();

  static const Map<BookingStatus, Set<BookingStatus>> transitions = {
    BookingStatus.pending: {
      BookingStatus.driverAssigned,
      BookingStatus.cancelled,
    },
    BookingStatus.driverAssigned: {
      BookingStatus.driverArriving,
      BookingStatus.cancelled,
    },
    BookingStatus.driverArriving: {
      BookingStatus.passengerOnBoard,
      BookingStatus.cancelled,
    },
    BookingStatus.passengerOnBoard: {BookingStatus.paymentConfirmation},
    BookingStatus.paymentConfirmation: {BookingStatus.completed},
    BookingStatus.completed: {},
    BookingStatus.cancelled: {},
  };

  static bool canTransition(BookingStatus current, BookingStatus next) {
    return transitions[current]?.contains(next) ?? false;
  }

  static bool isTerminal(BookingStatus status) {
    return transitions[status]?.isEmpty ?? true;
  }

  static bool isActive(BookingStatus status) {
    return !isTerminal(status);
  }
}
