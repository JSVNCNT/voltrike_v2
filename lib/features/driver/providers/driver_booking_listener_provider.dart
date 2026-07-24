import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/booking_repository.dart';
import '../services/driver_booking_listener.dart';

/// ===========================================================================
/// Driver Booking Listener Provider
///
/// Creates the listener responsible for discovering nearby
/// pending bookings.
///
/// NOTE:
/// This listener is ONLY for booking discovery.
/// It does NOT manage the driver's active booking.
/// ===========================================================================
final driverBookingListenerProvider =
    Provider<DriverBookingListener>(
  (ref) {
    return DriverBookingListener(
      bookingRepository: BookingRepository(),
      ref: ref,
    );
  },
);