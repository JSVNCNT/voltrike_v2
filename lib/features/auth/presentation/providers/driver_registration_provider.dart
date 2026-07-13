import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/driver_registration_controller.dart';
import 'auth_provider.dart';

final driverRegistrationControllerProvider =
    StateNotifierProvider<
        DriverRegistrationController,
        AsyncValue<void>>(
  (ref) {
    return DriverRegistrationController(
      authRepository: ref.read(
        authRepositoryProvider,
      ),
      userRepository: ref.read(
        userRepositoryProvider,
      ),
      driverRepository: ref.read(
        driverRepositoryProvider,
      ),
      vehicleRepository: ref.read(
        vehicleRepositoryProvider,
      ),
      storageRepository: ref.read(
        storageRepositoryProvider,
      ),
    );
  },
);