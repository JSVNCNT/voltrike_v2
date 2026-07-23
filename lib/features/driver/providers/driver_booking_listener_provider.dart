import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/booking_repository.dart';
import '../services/driver_booking_listener.dart';

final driverBookingListenerProvider =
    Provider<DriverBookingListener>(
  (ref) {
    return DriverBookingListener(
      bookingRepository:
          BookingRepository(),
      ref: ref,
    );
  },
);