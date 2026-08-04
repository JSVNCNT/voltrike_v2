import 'dart:developer' as developer;

import 'package:flutter_riverpod/legacy.dart';

import '../../../data/models/booking.dart';

/// ===========================================================================
/// Driver Incoming Booking
///
/// Stores the booking request currently waiting for the driver's response.
///
/// This provider is ONLY used for pending bookings.
///
/// Set by:
/// • DriverBookingListener
///
/// Cleared when:
/// • Driver accepts
/// • Driver declines
/// • Passenger cancels
/// • No pending bookings exist
///
/// Active bookings are handled by DriverCurrentBookingProvider.
/// ===========================================================================
class DriverIncomingBookingNotifier
    extends StateNotifier<Booking?> {
  DriverIncomingBookingNotifier() : super(null);

  void setBooking(Booking booking) {
    developer.log(
      'Incoming booking set: ${booking.bookingId}',
      name: 'DriverIncomingBookingProvider',
    );

    state = booking;
  }

  void clearBooking() {
    developer.log(
      'Incoming booking cleared',
      name: 'DriverIncomingBookingProvider',
    );

    state = null;
  }

  bool get hasBooking => state != null;
}

/// ===========================================================================
/// Provider
/// ===========================================================================

final driverIncomingBookingProvider =
    StateNotifierProvider<
        DriverIncomingBookingNotifier,
        Booking?>(
  (ref) => DriverIncomingBookingNotifier(),
);