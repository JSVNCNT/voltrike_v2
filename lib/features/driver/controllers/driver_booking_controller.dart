import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/services/voltrike_api.dart';
import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/driver_repository.dart';

import '../providers/driver_current_booking_provider.dart';
import '../providers/driver_incoming_booking_provider.dart';
import '../providers/driver_location_controller_provider.dart';
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
class DriverBookingController extends StateNotifier<AsyncValue<void>> {
  DriverBookingController({
    required BookingRepository bookingRepository,
    required DriverRepository driverRepository,
    required AuthRepository authRepository,
    required DriverCurrentBookingListener currentBookingListener,
    required Ref ref,
  }) : _bookingRepository = bookingRepository,
       _driverRepository = driverRepository,
       _authRepository = authRepository,
       _currentBookingListener = currentBookingListener,
       _ref = ref,
       super(const AsyncData(null));

  //==========================================================================
  // Dependencies
  //==========================================================================

  final BookingRepository _bookingRepository;
  final DriverRepository _driverRepository;
  final AuthRepository _authRepository;

  /// Keeps the active booking synchronized with Firestore.
  final DriverCurrentBookingListener _currentBookingListener;

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

      final driver = await _driverRepository.getDriver(firebaseUser.uid);
      if (driver == null || !driver.isApproved) {
        throw StateError(
          'Your driver account must be approved before going online.',
        );
      }

      await _ref
          .read(driverLocationControllerProvider.notifier)
          .startTracking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  Future<void> goOffline() async {
    state = const AsyncLoading();

    try {
      if (_ref.read(driverCurrentBookingProvider) != null) {
        throw StateError(
          'Complete or cancel the active trip before going offline.',
        );
      }

      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      await _ref.read(driverLocationControllerProvider.notifier).stopTracking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  //==========================================================================
  // Booking Actions
  //==========================================================================

  Future<void> acceptBooking(Booking booking) async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      await _bookingRepository.acceptBookingTransaction(
        bookingId: booking.bookingId,
      );

      // Start listening to the active booking.
      _currentBookingListener.startListening(booking.bookingId);

      // Remove pending booking.
      _ref.read(driverIncomingBookingProvider.notifier).clearBooking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  Future<bool> declineBooking(Booking booking) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.declineBookingOffer(
        bookingId: booking.bookingId,
      );
      _ref.read(driverIncomingBookingProvider.notifier).clearBooking();

      state = const AsyncData(null);
      return true;
    } on VoltrikeApiException catch (error, stackTrace) {
      final code = error.code?.replaceAll('-', '_').toLowerCase();
      if (code == 'failed_precondition' || error.statusCode == 412) {
        // Passenger cancellation or another driver's acceptance can race the
        // button tap. For this driver the desired outcome is already true:
        // the offer is no longer actionable, so dismiss it idempotently.
        _ref.read(driverIncomingBookingProvider.notifier).clearBooking();
        state = const AsyncData(null);
        return false;
      }
      state = AsyncError(error, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  /// Restores the driver's durable active booking after app restart.
  Future<Booking?> restoreCurrentBooking() async {
    final firebaseUser = _authRepository.currentUser;
    if (firebaseUser == null) return null;

    final driver = await _driverRepository.getDriver(firebaseUser.uid);
    final bookingId = driver?.currentBookingId;
    if (bookingId == null || bookingId.isEmpty) {
      _ref.read(driverCurrentBookingProvider.notifier).clearBooking();
      return null;
    }

    final booking = await _bookingRepository.getBooking(bookingId);
    final isActive =
        booking != null &&
        booking.driverId == firebaseUser.uid &&
        booking.status != BookingStatus.completed &&
        booking.status != BookingStatus.cancelled;
    if (!isActive) {
      _ref.read(driverCurrentBookingProvider.notifier).clearBooking();
      return null;
    }

    _ref.read(driverCurrentBookingProvider.notifier).setBooking(booking);
    _currentBookingListener.startListening(bookingId);
    return booking;
  }

  //==========================================================================
  // Trip Lifecycle
  //==========================================================================

  Future<void> arrived(Booking booking) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.transitionStatus(
        bookingId: booking.bookingId,
        allowedCurrentStatuses: const {BookingStatus.driverAssigned},
        nextStatus: BookingStatus.driverArriving,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  Future<void> startTrip(Booking booking) async {
    state = const AsyncLoading();

    try {
      await _bookingRepository.transitionStatus(
        bookingId: booking.bookingId,
        allowedCurrentStatuses: const {BookingStatus.driverArriving},
        nextStatus: BookingStatus.passengerOnBoard,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  Future<void> markPassengerNoShow(Booking booking) async {
    state = const AsyncLoading();
    try {
      await _bookingRepository.markNoShow(bookingId: booking.bookingId);
      await _currentBookingListener.stopListening();
      _ref.read(driverCurrentBookingProvider.notifier).clearBooking();
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> completeTrip(Booking booking) async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      await _bookingRepository.confirmCashReceived(booking.bookingId);

      // Stop listening to the booking.
      await _currentBookingListener.stopListening();

      // Clear active booking state.
      _ref.read(driverCurrentBookingProvider.notifier).clearBooking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }

  Future<void> confirmDropOff(Booking booking) async {
    state = const AsyncLoading();
    try {
      final stop = booking.activeDestinationStop;
      if (booking.hasMultipleDropoffs && !stop.isFinal) {
        await _bookingRepository.advanceToNextDropoff(
          booking.bookingId,
          stop.sequence,
        );
      } else {
        await _bookingRepository.transitionStatus(
          bookingId: booking.bookingId,
          allowedCurrentStatuses: const {BookingStatus.passengerOnBoard},
          nextStatus: BookingStatus.paymentConfirmation,
        );
      }
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  //==========================================================================
  // Cancel Trip
  //==========================================================================

  Future<void> cancelTrip(
    Booking booking, {
    String reasonCode = 'cancelled_by_driver',
    String? reasonDetail,
  }) async {
    state = const AsyncLoading();

    try {
      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        throw Exception('No authenticated driver.');
      }

      // Cancel booking.
      await _bookingRepository.cancelBooking(
        booking.bookingId,
        allowedCurrentStatuses: const {
          BookingStatus.driverAssigned,
          BookingStatus.driverArriving,
        },
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      );

      // Stop listening to the booking.
      await _currentBookingListener.stopListening();

      // Clear active booking state.
      _ref.read(driverCurrentBookingProvider.notifier).clearBooking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);

      rethrow;
    }
  }
}
