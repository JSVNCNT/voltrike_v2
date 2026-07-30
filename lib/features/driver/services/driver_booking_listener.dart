import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../providers/driver_incoming_booking_provider.dart';

/// ===========================================================================
/// Driver Booking Listener
///
/// Responsibility:
/// • Listen for nearby pending bookings.
/// • Store the incoming booking.
/// • Notify the UI that a booking request exists.
///
/// This listener DOES NOT manage active bookings.
/// Active bookings are handled by DriverCurrentBookingListener.
/// ===========================================================================
class DriverBookingListener {
  DriverBookingListener({
    required BookingRepository bookingRepository,
    required AuthRepository authRepository,
    required Ref ref,
  }) : _bookingRepository = bookingRepository,
       _authRepository = authRepository,
       _ref = ref;

  final BookingRepository _bookingRepository;
  final AuthRepository _authRepository;
  final Ref _ref;

  StreamSubscription<List<Booking>>? _subscription;
  Timer? _retryTimer;
  bool _shouldListen = false;

  //==========================================================================
  // Start Listening
  //==========================================================================

  void startListening() {
    _shouldListen = true;
    _retryTimer?.cancel();
    _retryTimer = null;

    final driverId = _authRepository.currentUser?.uid;
    if (driverId == null) return;
    developer.log(
      'Starting pending booking listener...',
      name: 'DriverBookingListener',
    );

    _subscription?.cancel();

    _subscription = _bookingRepository
        .watchDriverOffers(driverId)
        .listen(
          (bookings) {
            developer.log(
              '========================',
              name: 'DriverBookingListener',
            );

            developer.log(
              'Pending bookings: ${bookings.length}',
              name: 'DriverBookingListener',
            );

            //----------------------------------------------------------------------
            // No pending bookings
            //----------------------------------------------------------------------

            if (bookings.isEmpty) {
              developer.log(
                'No pending bookings.',
                name: 'DriverBookingListener',
              );

              _ref.read(driverIncomingBookingProvider.notifier).clearBooking();

              developer.log(
                'Trip state -> waitingBooking',
                name: 'DriverBookingListener',
              );

              return;
            }

            //----------------------------------------------------------------------
            // Incoming booking
            //----------------------------------------------------------------------

            final booking = bookings.first;

            developer.log(
              'Incoming booking received.',
              name: 'DriverBookingListener',
            );

            developer.log(
              'Booking ID : ${booking.bookingId}',
              name: 'DriverBookingListener',
            );

            developer.log(
              'Status     : ${booking.status}',
              name: 'DriverBookingListener',
            );

            developer.log(
              'Passenger  : ${booking.passengerName ?? booking.passengerId}',
              name: 'DriverBookingListener',
            );

            developer.log(
              'Saving booking to IncomingBookingProvider...',
              name: 'DriverBookingListener',
            );

            _ref
                .read(driverIncomingBookingProvider.notifier)
                .setBooking(booking);

            developer.log(
              'Updating trip state -> bookingReceived',
              name: 'DriverBookingListener',
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            // The booking document is readable only while this driver has an
            // active offer. Once it expires Firestore can reject an in-flight
            // document read; do not leave the listener permanently terminated.
            developer.log(
              'Offer listener error: $error',
              name: 'DriverBookingListener',
              stackTrace: stackTrace,
            );
            _ref.read(driverIncomingBookingProvider.notifier).clearBooking();
            if (!_shouldListen) return;
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 1), () {
              if (_shouldListen) startListening();
            });
          },
        );
  }

  //==========================================================================
  // Stop Listening
  //==========================================================================

  Future<void> stopListening() async {
    developer.log(
      'Stopping pending booking listener...',
      name: 'DriverBookingListener',
    );

    _shouldListen = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;

    _ref.read(driverIncomingBookingProvider.notifier).clearBooking();
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await stopListening();
  }
}
