import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/registration_repository.dart';
import '../../../../data/repositories/toda_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/repositories/vehicle_repository.dart';
import '../../../../data/repositories/storage_repository.dart';

/// ===========================================================================
/// Authentication
/// ===========================================================================

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// ===========================================================================
/// Users
/// ===========================================================================

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);

/// ===========================================================================
/// Passengers
/// ===========================================================================

final passengerRepositoryProvider = Provider<PassengerRepository>(
  (ref) => PassengerRepository(),
);

/// ===========================================================================
/// Registration
/// ===========================================================================

final registrationRepositoryProvider = Provider<RegistrationRepository>(
  (ref) => RegistrationRepository(),
);

/// ===========================================================================
/// Drivers
/// ===========================================================================

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => DriverRepository(),
);

/// ===========================================================================
/// Vehicles
/// ===========================================================================

final vehicleRepositoryProvider = Provider<VehicleRepository>(
  (ref) => VehicleRepository(),
);

/// ===========================================================================
/// Storage
/// ===========================================================================

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => StorageRepository(),
);

/// ===========================================================================
/// TODA
/// ===========================================================================

final todaRepositoryProvider = Provider<TodaRepository>(
  (ref) => TodaRepository(),
);
