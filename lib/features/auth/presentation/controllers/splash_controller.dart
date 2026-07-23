import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';

enum SplashDestination {
  intro,
  verifyEmail,
  passengerHome,
  driverHome,
  driverUnderReview,
}

class SplashController
    extends StateNotifier<AsyncValue<SplashDestination>> {
  SplashController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DriverRepository driverRepository,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _driverRepository = driverRepository,
        super(const AsyncLoading());

  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DriverRepository _driverRepository;

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

      final user = await _userRepository.getUser(
        firebaseUser.uid,
      );

      if (user == null || !user.isActive) {
        state = const AsyncData(
          SplashDestination.intro,
        );
        return;
      }

      // ==========================================================
      // Driver
      // ==========================================================

      if (user.isDriver) {
        final driver =
            await _driverRepository.getDriver(
          firebaseUser.uid,
        );

        if (driver == null) {
          state = const AsyncData(
            SplashDestination.intro,
          );
          return;
        }

        if (driver.isApproved) {
          state = const AsyncData(
            SplashDestination.driverHome,
          );
        } else {
          state = const AsyncData(
            SplashDestination.driverUnderReview,
          );
        }

        return;
      }

      // ==========================================================
      // Passenger
      // ==========================================================

      state = const AsyncData(
        SplashDestination.passengerHome,
      );
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );
    }
  }
}