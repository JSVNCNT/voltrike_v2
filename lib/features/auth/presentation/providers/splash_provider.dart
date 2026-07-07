import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/splash_controller.dart';
import 'auth_provider.dart';

final splashControllerProvider =
    StateNotifierProvider<SplashController, AsyncValue<SplashDestination>>(
  (ref) {
    return SplashController(
      authRepository: ref.read(authRepositoryProvider),
      userRepository: ref.read(userRepositoryProvider),
    );
  },
);