import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../data/models/booking.dart';

/// ===========================================================================
/// Booking Listener Service
///
/// Listens to booking changes in Firestore.
///
/// Used by:
/// • SearchingDriverScreen
/// • Driver Assigned Screen
/// ===========================================================================
class BookingListenerService {
  BookingListenerService._();

  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  static Stream<Booking?> listen(
    String bookingId,
  ) {
    return _firestore
        .collection('bookings')
        .doc(bookingId)
        .snapshots()
        .map(
      (snapshot) {
        developer.log(
          'Snapshot received for booking: $bookingId',
          name: 'BookingListenerService',
        );

        if (!snapshot.exists) {
          developer.log(
            'Booking not found.',
            name: 'BookingListenerService',
          );
          return null;
        }

        final booking = Booking.fromFirestore(snapshot);

        developer.log(
          'Booking status: ${booking.status}',
          name: 'BookingListenerService',
        );

        return booking;
      },
    );
  }
}