import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/user_repository.dart';

enum SplashDestination {
  intro,
  verifyEmail,
  passengerHome,
  driverHome,
}

class SplashController
    extends StateNotifier<AsyncValue<SplashDestination>> {
  SplashController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        super(const AsyncLoading());

  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  Future<void> checkSession() async {
    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        state = const AsyncData(
          SplashDestination.intro,
        );
        return;
      }

      await _authRepository.reloadUser();

      if (!_authRepository.isEmailVerified) {
        state = const AsyncData(
          SplashDestination.verifyEmail,
        );
        return;
      }

      final user =
          await _userRepository.getUser(firebaseUser.uid);

      if (user == null || !user.isActive) {
        state = const AsyncData(
          SplashDestination.intro,
        );
        return;
      }

      if (user.isDriver) {
        // Driver status (pending/approved/rejected/suspended)
        // will be checked through DriverRepository
        // after the Driver module is implemented.
        state = const AsyncData(
          SplashDestination.driverHome,
        );
        return;
      }

      state = const AsyncData(
        SplashDestination.passengerHome,
      );
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }
}