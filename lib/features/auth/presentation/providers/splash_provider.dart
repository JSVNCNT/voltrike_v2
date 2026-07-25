import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/booking_repository.dart';
import '../controllers/splash_controller.dart';
import 'auth_provider.dart';

final splashControllerProvider =
    StateNotifierProvider<
        SplashController,
        AsyncValue<SplashRecovery>>(
  (ref) {
    return SplashController(
      authRepository: ref.read(
        authRepositoryProvider,
      ),
      userRepository: ref.read(
        userRepositoryProvider,
      ),
      driverRepository: ref.read(
        driverRepositoryProvider,
      ),
      bookingRepository: BookingRepository(),
    );
  },
);
