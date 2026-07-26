import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../providers/booking_session_provider.dart';

/// ===========================================================================
/// Booking Controller
///
/// Creates passenger bookings and stores them in Firestore.
///
/// Returns the generated booking ID so the passenger app can
/// immediately begin listening for booking updates.
/// ===========================================================================
class BookingController extends StateNotifier<AsyncValue<void>> {
  BookingController({
    required BookingRepository bookingRepository,
    required AuthRepository authRepository,
  }) : _bookingRepository = bookingRepository,
       _authRepository = authRepository,
       super(const AsyncData(null));

  final BookingRepository _bookingRepository;

  final AuthRepository _authRepository;

  final Uuid _uuid = const Uuid();
  final UserRepository _userRepository = UserRepository();

  Future<String> createBooking({
    required BookingSession session,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLatitude,
    required double pickupLongitude,
  }) async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated passenger.');
      }

      if (session.destination == null) {
        throw Exception('Destination not selected.');
      }

      final profile = await _userRepository.getUser(firebaseUser.uid);

      final booking = Booking(
        bookingId: _uuid.v4(),
        passengerId: firebaseUser.uid,
        passengerName: profile?.fullName.trim().isNotEmpty == true
            ? profile!.fullName
            : (firebaseUser.displayName ?? firebaseUser.email ?? 'Passenger'),
        passengerPhone: profile?.phoneNumber,
        passengerPhotoUrl: profile?.profileImage,
        driverId: null,
        pickup: LatLng(pickupLatitude, pickupLongitude),
        destination: session.destination!,
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        distanceMeters: session.distanceMeters,
        estimatedFare: session.estimatedFare,
        additionalPassengers: session.additionalPassengers,
        baggageCount: session.baggageCount,
        isOutsideToda: session.isOutsideToda,
        status: BookingStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _bookingRepository.createBooking(booking);

      state = const AsyncData(null);

      return booking.bookingId;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  //==========================================================================
  // Cancel Booking
  //==========================================================================

  Future<void> cancelBooking(
    String bookingId, {
    String reasonCode = 'cancelled_by_passenger',
    String? reasonDetail,
  }) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.cancelBooking(
        bookingId,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }
}
