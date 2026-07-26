import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/booking_repository.dart';
import '../providers/driver_current_booking_provider.dart';

/// ===========================================================================
/// Driver Current Booking Listener
///
/// Listens to a single booking document after the driver accepts a booking.
/// Keeps driverCurrentBookingProvider synchronized with Firestore.
/// ===========================================================================
class DriverCurrentBookingListener {
  DriverCurrentBookingListener({
    required BookingRepository bookingRepository,
    required Ref ref,
  }) : _bookingRepository = bookingRepository,
       _ref = ref;

  final BookingRepository _bookingRepository;
  final Ref _ref;

  StreamSubscription<Booking?>? _subscription;

  String? _currentBookingId;

  //==========================================================================
  // Start Listening
  //==========================================================================

  void startListening(String bookingId) {
    // Already listening to this booking.
    if (_currentBookingId == bookingId && _subscription != null) {
      return;
    }

    _subscription?.cancel();
    _currentBookingId = bookingId;

    developer.log(
      'DriverCurrentBookingListener started for $bookingId',
      name: 'DriverCurrentBookingListener',
    );

    developer.log(
      'Listening to booking: $bookingId',
      name: 'DriverCurrentBookingListener',
    );

    _subscription = _bookingRepository
        .watchBooking(bookingId)
        .listen(
          (booking) {
            if (booking == null) {
              developer.log(
                'Booking deleted.',
                name: 'DriverCurrentBookingListener',
              );

              _clearStaleBooking();
              return;
            }

            // A terminal document is still retained for history, but it is never
            // an active ride. Keeping it in the local provider after a reconnect
            // leaves the driver home screen stuck on obsolete controls.
            if (booking.status == BookingStatus.completed ||
                booking.status == BookingStatus.cancelled) {
              developer.log(
                'Booking is terminal; clearing active ride state.',
                name: 'DriverCurrentBookingListener',
              );
              _clearStaleBooking();
              return;
            }

            developer.log(
              'Booking updated.',
              name: 'DriverCurrentBookingListener',
            );

            developer.log(
              'Status: ${booking.status}',
              name: 'DriverCurrentBookingListener',
            );

            _ref
                .read(driverCurrentBookingProvider.notifier)
                .setBooking(booking);
          },
          onError: (error, stackTrace) {
            developer.log(
              'Listener error: $error',
              name: 'DriverCurrentBookingListener',
            );
          },
        );
  }

  void _clearStaleBooking() {
    _ref.read(driverCurrentBookingProvider.notifier).clearBooking();
    // Allow a future lifecycle assignment to subscribe even if it reuses the
    // same ID in a test/emulator fixture. Do not await cancellation inside a
    // stream callback.
    _subscription?.cancel();
    _subscription = null;
    _currentBookingId = null;
  }

  //==========================================================================
  // Stop Listening
  //==========================================================================

  Future<void> stopListening() async {
    developer.log(
      'Stopping booking listener.',
      name: 'DriverCurrentBookingListener',
    );

    await _subscription?.cancel();

    _subscription = null;
    _currentBookingId = null;
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await stopListening();
  }
}
