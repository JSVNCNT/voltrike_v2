import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';
import '../controllers/driver_booking_controller.dart';

/// ===========================================================================
/// Booking Repository Provider
/// ===========================================================================

final driverBookingRepositoryProvider =
    Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

/// ===========================================================================
/// Driver Repository Provider
/// ===========================================================================

final driverRepositoryProvider =
    Provider<DriverRepository>(
  (ref) => DriverRepository(),
);

/// ===========================================================================
/// Auth Repository Provider
/// ===========================================================================

final driverAuthRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// ===========================================================================
/// Driver Booking Controller Provider
/// ===========================================================================

final driverBookingControllerProvider =
    StateNotifierProvider<
        DriverBookingController,
        AsyncValue<void>>(
  (ref) {
    return DriverBookingController(
      bookingRepository: ref.read(
        driverBookingRepositoryProvider,
      ),
      driverRepository: ref.read(
        driverRepositoryProvider,
      ),
      authRepository: ref.read(
        driverAuthRepositoryProvider,
      ),
    );
  },
);