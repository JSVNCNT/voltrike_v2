import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/driver_rating.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_rating_repository.dart';

/// ===========================================================================
/// Driver Rating Controller
///
/// Handles submitting passenger ratings after a completed trip.
///
/// Flow:
///
/// Passenger
///      ↓
/// Rating Screen
///      ↓
/// Booking loaded
///      ↓
/// Driver ID extracted
///      ↓
/// Rating saved to Firestore
/// ===========================================================================
class DriverRatingController
    extends StateNotifier<AsyncValue<void>> {
  DriverRatingController({
    required DriverRatingRepository
        driverRatingRepository,
    required BookingRepository
        bookingRepository,
    required AuthRepository
        authRepository,
  })  : _driverRatingRepository =
            driverRatingRepository,
        _bookingRepository =
            bookingRepository,
        _authRepository =
            authRepository,
        super(const AsyncData(null));

  final DriverRatingRepository
      _driverRatingRepository;

  final BookingRepository
      _bookingRepository;

  final AuthRepository
      _authRepository;

  //==========================================================================
  // Submit Rating
  //==========================================================================

  Future<void> submitRating({
    required String bookingId,
    required int rating,
    required String comment,
  }) async {
    state = const AsyncLoading();

    try {
      final passenger =
          _authRepository.currentUser;

      if (passenger == null) {
        throw Exception(
          'No authenticated passenger.',
        );
      }

      final booking =
          await _bookingRepository
              .getBooking(
        bookingId,
      );

      if (booking == null) {
        throw Exception(
          'Booking not found.',
        );
      }

      if (booking.driverId == null) {
        throw Exception(
          'Booking has no assigned driver.',
        );
      }

      final driverRating =
          DriverRating(
        ratingId:
            DateTime.now()
                .millisecondsSinceEpoch
                .toString(),
        bookingId: booking.bookingId,
        driverId:
            booking.driverId!,
        passengerId:
            passenger.uid,
        rating: rating,
        comment:
            comment.trim(),
        createdAt:
            DateTime.now(),
      );

      await _driverRatingRepository
          .createRating(
        driverRating,
      );

      state =
          const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(
        error,
        stackTrace,
      );

      rethrow;
    }
  }
}