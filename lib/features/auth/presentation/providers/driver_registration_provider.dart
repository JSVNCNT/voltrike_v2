import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/driver_registration_controller.dart';
import 'auth_provider.dart';

final driverRegistrationControllerProvider =
    StateNotifierProvider<DriverRegistrationController, AsyncValue<void>>((
      ref,
    ) {
      return DriverRegistrationController(
        authRepository: ref.read(authRepositoryProvider),
        registrationRepository: ref.read(registrationRepositoryProvider),
        storageRepository: ref.read(storageRepositoryProvider),
      );
    });
