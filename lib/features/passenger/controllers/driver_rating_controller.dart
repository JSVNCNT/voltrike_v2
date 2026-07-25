import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
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
      if (rating < 1 || rating > 5) {
        throw ArgumentError.value(
          rating,
          'rating',
          'Rating must be between 1 and 5.',
        );
      }

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

      if (booking.passengerId != passenger.uid) {
        throw Exception('You cannot rate this booking.');
      }

      if (booking.status != BookingStatus.completed) {
        throw Exception('Only completed trips can be rated.');
      }

      if (await _driverRatingRepository.hasRatingForBooking(
        bookingId: bookingId,
        passengerId: passenger.uid,
      )) {
        throw Exception('This trip has already been rated.');
      }

      final driverRating =
          DriverRating(
        ratingId: '${booking.bookingId}_${passenger.uid}',
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
