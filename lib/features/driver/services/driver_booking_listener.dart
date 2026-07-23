import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/booking_repository.dart';
import '../providers/driver_current_booking_provider.dart';
import '../providers/driver_trip_provider.dart';

/// ===========================================================================
/// Driver Booking Listener
///
/// Listens for nearby pending bookings and updates the driver state.
///
/// Future:
/// • Filter by TODA
/// • Filter by geofence
/// • Filter by driver availability
/// • Filter by booking distance
/// ===========================================================================
class DriverBookingListener {
  DriverBookingListener({
    required BookingRepository bookingRepository,
    required Ref ref,
  })  : _bookingRepository = bookingRepository,
        _ref = ref;

  final BookingRepository _bookingRepository;
  final Ref _ref;

  StreamSubscription<List<Booking>>? _subscription;

  //==========================================================================
  // Start Listening
  //==========================================================================

  void startListening() {
    _subscription?.cancel();

    _subscription =
        _bookingRepository
            .watchPendingBookings()
            .listen(
      (bookings) {
        if (bookings.isEmpty) {
          _ref
              .read(
                driverCurrentBookingProvider.notifier,
              )
              .clearBooking();

          _ref
              .read(
                driverTripProvider.notifier,
              )
              .waitingBooking();

          return;
        }

        final booking = bookings.first;

        _ref
            .read(
              driverCurrentBookingProvider.notifier,
            )
            .setBooking(
              booking,
            );

        _ref
            .read(
              driverTripProvider.notifier,
            )
            .bookingReceived();
      },
    );
  }

  //==========================================================================
  // Stop Listening
  //==========================================================================

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await stopListening();
  }
}