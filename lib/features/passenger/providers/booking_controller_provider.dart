import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/booking_repository.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../controllers/booking_controller.dart';

/// ===========================================================================
/// Booking Repository Provider
/// ===========================================================================
final bookingRepositoryProvider =
    Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

/// ===========================================================================
/// Booking Controller Provider
/// ===========================================================================
final bookingControllerProvider =
    StateNotifierProvider<
        BookingController,
        AsyncValue<void>>(
  (ref) {
    return BookingController(
      bookingRepository:
          ref.read(
        bookingRepositoryProvider,
      ),
      authRepository:
          ref.read(
        authRepositoryProvider,
      ),
    );
  },
);