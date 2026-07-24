import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/booking_repository.dart';
import '../providers/driver_incoming_booking_provider.dart';
import '../providers/driver_trip_provider.dart';

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
    developer.log(
      'Starting pending booking listener...',
      name: 'DriverBookingListener',
    );

    _subscription?.cancel();

    _subscription = _bookingRepository
        .watchPendingBookings()
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

          _ref
              .read(
                driverIncomingBookingProvider.notifier,
              )
              .clearBooking();

          _ref
              .read(
                driverTripProvider.notifier,
              )
              .waitingBooking();

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
          'Passenger  : ${booking.passengerId}',
          name: 'DriverBookingListener',
        );

        developer.log(
          'Saving booking to IncomingBookingProvider...',
          name: 'DriverBookingListener',
        );

        _ref
            .read(
              driverIncomingBookingProvider.notifier,
            )
            .setBooking(booking);

        developer.log(
          'Updating trip state -> bookingReceived',
          name: 'DriverBookingListener',
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
    developer.log(
      'Stopping pending booking listener...',
      name: 'DriverBookingListener',
    );

    await _subscription?.cancel();
    _subscription = null;

    _ref
        .read(
          driverIncomingBookingProvider.notifier,
        )
        .clearBooking();
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await stopListening();
  }
}