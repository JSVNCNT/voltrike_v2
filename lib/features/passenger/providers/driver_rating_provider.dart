import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_rating_repository.dart';

import '../controllers/driver_rating_controller.dart';

/// ===========================================================================
/// Driver Rating Repository Provider
/// ===========================================================================

final driverRatingRepositoryProvider =
    Provider<DriverRatingRepository>(
  (ref) => DriverRatingRepository(),
);

/// ===========================================================================
/// Booking Repository Provider
/// ===========================================================================

final bookingRepositoryProvider =
    Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

/// ===========================================================================
/// Passenger Auth Repository Provider
/// ===========================================================================

final passengerAuthRepositoryProvider =
    Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// ===========================================================================
/// Driver Rating Controller Provider
///
/// Handles:
/// • Submit Rating
/// • Loading State
/// • Error State
/// ===========================================================================

final driverRatingControllerProvider =
    StateNotifierProvider<
        DriverRatingController,
        AsyncValue<void>>(
  (ref) {
    return DriverRatingController(
      driverRatingRepository:
          ref.read(
        driverRatingRepositoryProvider,
      ),
      bookingRepository:
          ref.read(
        bookingRepositoryProvider,
      ),
      authRepository:
          ref.read(
        passengerAuthRepositoryProvider,
      ),
    );
  },
);