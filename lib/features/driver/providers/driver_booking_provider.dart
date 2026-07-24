import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';
import '../../../data/repositories/toda_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/vehicle_repository.dart';

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
/// User Repository Provider
/// ===========================================================================

final userRepositoryProvider =
    Provider<UserRepository>(
  (ref) => UserRepository(),
);

/// ===========================================================================
/// Vehicle Repository Provider
/// ===========================================================================

final vehicleRepositoryProvider =
    Provider<VehicleRepository>(
  (ref) => VehicleRepository(),
);

/// ===========================================================================
/// TODA Repository Provider
/// ===========================================================================

final todaRepositoryProvider =
    Provider<TodaRepository>(
  (ref) => TodaRepository(),
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
      userRepository: ref.read(
        userRepositoryProvider,
      ),
      vehicleRepository: ref.read(
        vehicleRepositoryProvider,
      ),
      todaRepository: ref.read(
        todaRepositoryProvider,
      ),
      authRepository: ref.read(
        driverAuthRepositoryProvider,
      ),
    );
  },
);