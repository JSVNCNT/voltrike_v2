import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';
import '../../../data/repositories/toda_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/vehicle_repository.dart';

/// ===========================================================================
/// Driver Booking Controller
/// ===========================================================================
class DriverBookingController
    extends StateNotifier<AsyncValue<void>> {
  DriverBookingController({
    required BookingRepository bookingRepository,
    required DriverRepository driverRepository,
    required UserRepository userRepository,
    required VehicleRepository vehicleRepository,
    required TodaRepository todaRepository,
    required AuthRepository authRepository,
  })  : _bookingRepository = bookingRepository,
        _driverRepository = driverRepository,
        _userRepository = userRepository,
        _vehicleRepository = vehicleRepository,
        _todaRepository = todaRepository,
        _authRepository = authRepository,
        super(const AsyncData(null));

  final BookingRepository _bookingRepository;
  final DriverRepository _driverRepository;
  final UserRepository _userRepository;
  final VehicleRepository _vehicleRepository;
  final TodaRepository _todaRepository;
  final AuthRepository _authRepository;

  //==========================================================================
  // Driver Availability
  //==========================================================================

  Future<void> goOnline() async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      await _driverRepository.goOnline(
        firebaseUser.uid,
      );

      await _driverRepository.setAvailable(
        uid: firebaseUser.uid,
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
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      await _driverRepository.goOffline(
        firebaseUser.uid,
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
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      final driver = await _driverRepository.getDriver(
        firebaseUser.uid,
      );

      if (driver == null) {
        throw Exception('Driver record not found.');
      }

      final appUser = await _userRepository.getUser(
        firebaseUser.uid,
      );

      if (appUser == null) {
        throw Exception('User record not found.');
      }

      final vehicle =
          await _vehicleRepository.getVehicle(
        driver.vehicleId,
      );

      if (vehicle == null) {
        throw Exception('Vehicle not found.');
      }

      final toda = await _todaRepository.getToda(
        driver.todaId,
      );

      if (toda == null) {
        throw Exception('TODA not found.');
      }

      await _bookingRepository.assignDriver(
        bookingId: booking.bookingId,
        driverId: firebaseUser.uid,
        driverName: appUser.fullName,
        driverPhotoUrl: appUser.profileImage,
        driverRating: driver.rating,
        vehicleNumber: vehicle.vehicleNumber,
        plateNumber: vehicle.plateNumber,
        todaName: toda.name,
      );

      await _driverRepository.assignBooking(
        uid: firebaseUser.uid,
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
      final firebaseUser =
          _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _bookingRepository.completeBooking(
        booking.bookingId,
      );

      await _driverRepository.clearBooking(
        firebaseUser.uid,
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
      final firebaseUser =
          _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await _bookingRepository.cancelBooking(
        booking.bookingId,
      );

      await _driverRepository.clearBooking(
        firebaseUser.uid,
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