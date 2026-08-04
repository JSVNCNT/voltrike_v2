import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/repositories/auth_repository.dart';
import '../controllers/driver_location_controller.dart';

final driverLocationAuthRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final driverLocationControllerProvider =
    StateNotifierProvider<
        DriverLocationController,
        DriverLocationState>(
  (ref) {
    return DriverLocationController(
      authRepository: ref.read(
        driverLocationAuthRepositoryProvider,
      ),
    );
  },
);
