import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';
import '../controllers/driver_location_controller.dart';

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
      authRepository: ref.read(
        driverLocationAuthRepositoryProvider,
      ),
    );
  },
);
