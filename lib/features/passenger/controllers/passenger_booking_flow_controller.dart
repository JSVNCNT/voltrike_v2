import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';

/// ===========================================================================
/// Passenger Booking Flow Controller
///
/// Determines the current passenger booking flow based on the
/// Firestore booking status.
///
/// Used by:
/// • SearchingDriverScreen
/// • Passenger Home
/// • Future Driver Tracking
/// ===========================================================================
class PassengerBookingFlowController
    extends StateNotifier<BookingStatus?> {
  PassengerBookingFlowController()
      : super(null);

  void update(Booking? booking) {
    state = booking?.status;
  }

  void clear() {
    state = null;
  }
}

final passengerBookingFlowProvider =
    StateNotifierProvider<
        PassengerBookingFlowController,
        BookingStatus?>(
  (ref) =>
      PassengerBookingFlowController(),
);