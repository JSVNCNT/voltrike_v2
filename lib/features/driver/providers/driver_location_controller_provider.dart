import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/driver_repository.dart';
import '../controllers/driver_location_controller.dart';

final driverRepositoryProvider =
    Provider<DriverRepository>(
  (ref) => DriverRepository(),
);

final driverLocationAuthRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final driverLocationControllerProvider =
    StateNotifierProvider<
        DriverLocationController,
        AsyncValue<void>>(
  (ref) {
    return DriverLocationController(
      driverRepository: ref.read(
        driverRepositoryProvider,
      ),
      authRepository: ref.read(
        driverLocationAuthRepositoryProvider,
      ),
    );
  },
);