import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';

enum SplashDestination {
  intro,
  verifyEmail,
  passengerHome,
  driverHome,
  driverUnderReview,
  accountSuspended,
  passengerActiveBooking,
  driverActiveBooking,
}

class SplashRecovery {
  const SplashRecovery({required this.destination, this.bookingId});

  final SplashDestination destination;
  final String? bookingId;
}

class SplashController extends StateNotifier<AsyncValue<SplashRecovery>> {
  SplashController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DriverRepository driverRepository,
    required BookingRepository bookingRepository,
  }) : _authRepository = authRepository,
       _userRepository = userRepository,
       _driverRepository = driverRepository,
       _bookingRepository = bookingRepository,
       super(const AsyncLoading());

  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DriverRepository _driverRepository;
  final BookingRepository _bookingRepository;

  Future<void> checkSession() async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        _setDestination(SplashDestination.intro);
        return;
      }

      await _authRepository.reloadUser();

      if (!_authRepository.isEmailVerified) {
        _setDestination(SplashDestination.verifyEmail);
        return;
      }

      final user = await _userRepository.getUser(firebaseUser.uid);

      if (user == null || !user.isActive) {
        _setDestination(
          user == null
              ? SplashDestination.intro
              : SplashDestination.accountSuspended,
        );
        return;
      }

      // ==========================================================
      // Driver
      // ==========================================================

      if (user.isDriver) {
        final driver = await _driverRepository.getDriver(firebaseUser.uid);

        if (driver == null) {
          _setDestination(SplashDestination.intro);
          return;
        }

        if (driver.isSuspended) {
          _setDestination(SplashDestination.accountSuspended);
        } else if (driver.isApproved) {
          final bookingId = driver.currentBookingId;
          if (bookingId != null && bookingId.isNotEmpty) {
            final booking = await _bookingRepository.getBooking(bookingId);
            final isActive =
                booking != null &&
                booking.driverId == firebaseUser.uid &&
                booking.status != BookingStatus.completed &&
                booking.status != BookingStatus.cancelled;
            if (isActive) {
              _setDestination(
                SplashDestination.driverActiveBooking,
                bookingId: bookingId,
              );
              return;
            }
          }

          _setDestination(SplashDestination.driverHome);
        } else {
          _setDestination(SplashDestination.driverUnderReview);
        }

        return;
      }

      // ==========================================================
      // Passenger
      // ==========================================================

      final booking = await _bookingRepository
          .getActiveBookingForPassenger(firebaseUser.uid)
          .timeout(const Duration(seconds: 15));
      if (booking != null) {
        _setDestination(
          SplashDestination.passengerActiveBooking,
          bookingId: booking.bookingId,
        );
        return;
      }

      _setDestination(SplashDestination.passengerHome);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }

  void _setDestination(SplashDestination destination, {String? bookingId}) {
    state = AsyncData(
      SplashRecovery(destination: destination, bookingId: bookingId),
    );
  }
}
