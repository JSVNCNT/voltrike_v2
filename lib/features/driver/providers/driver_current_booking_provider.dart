import 'package:flutter_riverpod/legacy.dart';

import '../../../data/models/booking.dart';

/// ===========================================================================
/// Driver Current Booking
///
/// Stores the booking currently assigned to the driver.
///
/// This provider is shared by:
/// • DriverHomeScreen
/// • DriverBottomSheet
/// • DriverMapView
/// • BookingRequestCard
/// ===========================================================================
class DriverCurrentBookingNotifier
    extends StateNotifier<Booking?> {
  DriverCurrentBookingNotifier()
      : super(null);

  /// Assign a booking to the driver.
  void setBooking(
    Booking booking,
  ) {
    state = booking;
  }

  /// Clear the current booking.
  void clearBooking() {
    state = null;
  }

  /// Whether the driver currently has a booking.
  bool get hasBooking =>
      state != null;
}

/// ===========================================================================
/// Driver Current Booking Provider
/// ===========================================================================

final driverCurrentBookingProvider =
    StateNotifierProvider<
        DriverCurrentBookingNotifier,
        Booking?>(
  (ref) =>
      DriverCurrentBookingNotifier(),
);