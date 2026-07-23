import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';

/// ===========================================================================
/// Driver Booking Controller
///
/// Handles the driver's booking lifecycle.
///
/// Flow:
///
/// Offline
///     ↓
/// Online
///     ↓
/// Listen for Bookings
///     ↓
/// Accept / Decline
///     ↓
/// Arrived
///     ↓
/// Start Trip
///     ↓
/// Complete Trip
///     ↓
/// Back Online
/// ===========================================================================
class DriverBookingController
    extends StateNotifier<AsyncValue<void>> {
  DriverBookingController({
    required BookingRepository bookingRepository,
    required DriverRepository driverRepository,
    required AuthRepository authRepository,
  })  : _bookingRepository = bookingRepository,
        _driverRepository = driverRepository,
        _authRepository = authRepository,
        super(const AsyncData(null));

  final BookingRepository _bookingRepository;
  final DriverRepository _driverRepository;
  final AuthRepository _authRepository;

  //==========================================================================
  // Driver Availability
  //==========================================================================

  Future<void> goOnline() async {
    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _driverRepository.goOnline(
        driver.uid,
      );

      await _driverRepository.setAvailable(
        uid: driver.uid,
        available: true,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  Future<void> goOffline() async {
    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _driverRepository.goOffline(
        driver.uid,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  //==========================================================================
  // Booking Actions
  //==========================================================================

  Future<void> acceptBooking(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _bookingRepository.assignDriver(
        bookingId: booking.bookingId,
        driverId: driver.uid,
      );

      await _driverRepository.assignBooking(
        uid: driver.uid,
        bookingId: booking.bookingId,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  Future<void> declineBooking(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.updateStatus(
        bookingId: booking.bookingId,
        status: BookingStatus.pending,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  //==========================================================================
  // Trip Lifecycle
  //==========================================================================

  Future<void> arrived(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.updateStatus(
        bookingId: booking.bookingId,
        status: BookingStatus.driverArriving,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  Future<void> startTrip(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.updateStatus(
        bookingId: booking.bookingId,
        status: BookingStatus.passengerOnBoard,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  Future<void> completeTrip(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _bookingRepository.completeBooking(
        booking.bookingId,
      );

      await _driverRepository.clearBooking(
        driver.uid,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  //==========================================================================
  // Cancel Trip
  //==========================================================================

  Future<void> cancelTrip(
    Booking booking,
  ) async {
    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _bookingRepository.cancelBooking(
        booking.bookingId,
      );

      await _driverRepository.clearBooking(
        driver.uid,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }
}