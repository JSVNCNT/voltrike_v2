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

  /// Returns the most meaningful timestamp for a terminal booking.
  static DateTime terminalDate(Booking booking) {
    return switch (booking.status) {
      BookingStatus.completed => booking.completedAt ?? booking.updatedAt,
      BookingStatus.cancelled => booking.cancelledAt ?? booking.updatedAt,
      _ => booking.updatedAt,
    };
  }

  /// Keeps completed and cancelled bookings and orders the newest first.
  static List<Booking> terminalHistory(Iterable<Booking> bookings) {
    final history = bookings.where((booking) {
      return isTerminal(booking.status);
    }).toList();

    history.sort((a, b) => terminalDate(b).compareTo(terminalDate(a)));
    return history;
  }
}
