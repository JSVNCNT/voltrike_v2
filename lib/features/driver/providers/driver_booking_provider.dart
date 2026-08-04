import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';

import '../controllers/driver_booking_controller.dart';
import 'driver_current_booking_listener_provider.dart';

/// ===========================================================================
/// Booking Repository Provider
/// ===========================================================================

final driverBookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

/// ===========================================================================
/// Driver Repository Provider
/// ===========================================================================

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => DriverRepository(),
);

/// ===========================================================================
/// Auth Repository Provider
/// ===========================================================================

final driverAuthRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// ===========================================================================
/// Driver Booking Controller Provider
/// ===========================================================================

final driverBookingControllerProvider =
    StateNotifierProvider<DriverBookingController, AsyncValue<void>>((ref) {
      return DriverBookingController(
        bookingRepository: ref.read(driverBookingRepositoryProvider),
        driverRepository: ref.read(driverRepositoryProvider),
        authRepository: ref.read(driverAuthRepositoryProvider),

        // NEW
        currentBookingListener: ref.read(driverCurrentBookingListenerProvider),

        // NEW
        ref: ref,
      );
    });
