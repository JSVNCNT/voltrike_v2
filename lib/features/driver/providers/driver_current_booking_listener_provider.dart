import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/booking_repository.dart';
import '../services/driver_current_booking_listener.dart';

/// ===========================================================================
/// Driver Current Booking Listener Provider
///
/// Creates the listener responsible for tracking the
/// driver's active booking.
///
/// This listens to:
/// BookingRepository.watchBooking(bookingId)
/// ===========================================================================
final driverCurrentBookingListenerProvider =
    Provider<DriverCurrentBookingListener>(
  (ref) {
    return DriverCurrentBookingListener(
      bookingRepository: BookingRepository(),
      ref: ref,
    );
  },
);