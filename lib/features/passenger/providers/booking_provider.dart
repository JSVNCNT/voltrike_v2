import 'package:flutter_riverpod/legacy.dart';

/// ===========================================================================
/// Passenger Booking UI State
///
/// Temporary UI state used by the passenger application.
///
/// This is DIFFERENT from the Firestore BookingStatus
/// located in:
///
/// data/models/booking.dart
/// ===========================================================================
enum PassengerBookingState {
  idle,
  selectingDestination,
  estimatingFare,
  searchingDriver,
  driverAssigned,
  driverArriving,
  inProgress,
  completed,
  cancelled,
}

class BookingNotifier
    extends StateNotifier<PassengerBookingState> {
  BookingNotifier()
      : super(
          PassengerBookingState.idle,
        );

  void update(
    PassengerBookingState state,
  ) {
    this.state = state;
  }

  void reset() {
    state = PassengerBookingState.idle;
  }
}

final bookingProvider =
    StateNotifierProvider<
        BookingNotifier,
        PassengerBookingState>(
  (ref) => BookingNotifier(),
);