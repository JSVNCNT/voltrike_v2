import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';
import '../../../data/repositories/toda_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/vehicle_repository.dart';

import '../providers/driver_current_booking_provider.dart';
import '../providers/driver_incoming_booking_provider.dart';
import '../services/driver_current_booking_listener.dart';

/// ===========================================================================
/// Driver Booking Controller
///
/// Responsibilities
/// • Driver Availability
/// • Accept / Decline Bookings
/// • Trip Lifecycle
/// • Coordinate Active Booking State
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
    required DriverCurrentBookingListener currentBookingListener,
    required Ref ref,
  })  : _bookingRepository = bookingRepository,
        _driverRepository = driverRepository,
        _userRepository = userRepository,
        _vehicleRepository = vehicleRepository,
        _todaRepository = todaRepository,
        _authRepository = authRepository,
        _currentBookingListener = currentBookingListener,
        _ref = ref,
        super(const AsyncData(null));

  //==========================================================================
  // Dependencies
  //==========================================================================

  final BookingRepository _bookingRepository;
  final DriverRepository _driverRepository;
  final UserRepository _userRepository;
  final VehicleRepository _vehicleRepository;
  final TodaRepository _todaRepository;
  final AuthRepository _authRepository;

  /// Keeps the active booking synchronized with Firestore.
  final DriverCurrentBookingListener
      _currentBookingListener;

  /// Access to Riverpod providers.
  final Ref _ref;

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
    if (_ref.read(driverCurrentBookingProvider) != null) {
      throw StateError('Complete or cancel the active trip before going offline.');
    }

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

    await _bookingRepository.acceptBookingTransaction(
      bookingId: booking.bookingId,
      driverId: firebaseUser.uid,
      driverName: appUser.fullName,
      driverPhotoUrl: appUser.profileImage,
      driverRating: driver.rating,
      vehicleNumber: vehicle.vehicleNumber,
      plateNumber: vehicle.plateNumber,
      todaName: toda.name,
    );

    // Start listening to the active booking.
    _currentBookingListener.startListening(
      booking.bookingId,
    );

    // Remove pending booking.
    _ref
        .read(
          driverIncomingBookingProvider.notifier,
        )
        .clearBooking();

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
    // Declining is driver-local until offer records are introduced. Never
    // rewrite a shared pending booking, which could race with acceptance.
    _ref
        .read(
          driverIncomingBookingProvider.notifier,
        )
        .clearBooking();

    state = const AsyncData(null);
  } catch (e, stackTrace) {
    state = AsyncError(
      e,
      stackTrace,
    );

    rethrow;
  }
}

/// Restores the driver's durable active booking after app restart.
Future<void> restoreCurrentBooking() async {
  final firebaseUser = _authRepository.currentUser;
  if (firebaseUser == null) return;

  final driver = await _driverRepository.getDriver(firebaseUser.uid);
  final bookingId = driver?.currentBookingId;
  if (bookingId == null || bookingId.isEmpty) return;

  _currentBookingListener.startListening(bookingId);
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

    // Complete booking.
    await _bookingRepository.completeBooking(
      booking.bookingId,
    );

    // Remove booking from driver.
    await _driverRepository.clearBooking(
      firebaseUser.uid,
    );

    // Stop listening to the booking.
    await _currentBookingListener.stopListening();

    // Clear active booking state.
    _ref
        .read(
          driverCurrentBookingProvider.notifier,
        )
        .clearBooking();

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

    // Cancel booking.
    await _bookingRepository.cancelBooking(
      booking.bookingId,
    );

    // Remove booking from driver.
    await _driverRepository.clearBooking(
      firebaseUser.uid,
    );

    // Stop listening to the booking.
    await _currentBookingListener.stopListening();

    // Clear active booking state.
    _ref
        .read(
          driverCurrentBookingProvider.notifier,
        )
        .clearBooking();

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
