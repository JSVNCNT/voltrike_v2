import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';

/// ===========================================================================
/// Passenger Booking Flow Controller
///
/// Stores the current booking status for the passenger.
///
/// This provider should only be updated from listeners, controllers,
/// or user actions—not during a widget's build method.
/// ===========================================================================
class PassengerBookingFlowController
    extends StateNotifier<BookingStatus?> {
  PassengerBookingFlowController() : super(null);

  /// Updates the current booking status.
  void updateStatus(BookingStatus? status) {
    if (state == status) return;

    state = status;
  }

  /// Clears the current booking status.
  void clear() {
    if (state == null) return;

    state = null;
  }
}

final passengerBookingFlowProvider =
    StateNotifierProvider<
        PassengerBookingFlowController,
        BookingStatus?>(
  (ref) => PassengerBookingFlowController(),
);