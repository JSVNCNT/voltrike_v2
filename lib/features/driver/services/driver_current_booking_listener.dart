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
  })  : _bookingRepository = bookingRepository,
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
    if (_currentBookingId == bookingId &&
        _subscription != null) {
      return;
    }

    _subscription?.cancel();

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

          _ref
              .read(
                driverCurrentBookingProvider.notifier,
              )
              .clearBooking();

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
            .read(
              driverCurrentBookingProvider.notifier,
            )
            .setBooking(
              booking,
            );
      },
      onError: (error, stackTrace) {
        developer.log(
          'Listener error: $error',
          name: 'DriverCurrentBookingListener',
        );
      },
    );
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