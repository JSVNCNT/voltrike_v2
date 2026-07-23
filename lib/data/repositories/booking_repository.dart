import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/booking.dart';

/// ===========================================================================
/// Booking Repository
///
/// Handles all Firestore operations for bookings.
///
/// Collection:
/// bookings/
///
/// Used by:
/// • Passenger App
/// • Driver App
/// • Dashboard
/// • Trip History
/// • Reports
/// • Admin Portal
/// ===========================================================================
class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
  }) : _firestore =
            firestore ??
            FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>>
      get _collection =>
          _firestore.collection(
            'bookings',
          );

  //==========================================================================
  // Create Booking
  //==========================================================================

  Future<void> createBooking(
    Booking booking,
  ) async {
    await _collection
        .doc(
          booking.bookingId,
        )
        .set(
          booking.toFirestore(),
        );
  }

  //==========================================================================
  // Get Booking
  //==========================================================================

  Future<Booking?> getBooking(
    String bookingId,
  ) async {
    final doc =
        await _collection
            .doc(
              bookingId,
            )
            .get();

    if (!doc.exists) {
      return null;
    }

    return Booking.fromFirestore(
      doc,
    );
  }

  //==========================================================================
  // Watch Booking
  //==========================================================================

  Stream<Booking?> watchBooking(
    String bookingId,
  ) {
    return _collection
        .doc(
          bookingId,
        )
        .snapshots()
        .map(
      (doc) {
        if (!doc.exists) {
          return null;
        }

        return Booking.fromFirestore(
          doc,
        );
      },
    );
  }

  //==========================================================================
  // Watch Pending Bookings
  //==========================================================================

  Stream<List<Booking>>
      watchPendingBookings() {
    return _collection
        .where(
          'status',
          isEqualTo:
              BookingStatus
                  .pending
                  .name,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs
            .map(
              Booking.fromFirestore,
            )
            .toList();
      },
    );
  }

  //==========================================================================
  // Watch Driver Bookings
  //==========================================================================

  Stream<List<Booking>>
      watchDriverBookings(
    String driverId,
  ) {
    return _collection
        .where(
          'driverId',
          isEqualTo: driverId,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs
            .map(
              Booking.fromFirestore,
            )
            .toList();
      },
    );
  }

  //==========================================================================
  // Watch Passenger Bookings
  //==========================================================================

  Stream<List<Booking>>
      watchPassengerBookings(
    String passengerId,
  ) {
    return _collection
        .where(
          'passengerId',
          isEqualTo: passengerId,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs
            .map(
              Booking.fromFirestore,
            )
            .toList();
      },
    );
  }

    //==========================================================================
  // Passenger Trip History
  //==========================================================================

  Stream<List<Booking>>
      bookingsForPassenger(
    String passengerId,
  ) {
    return _collection
        .where(
          'passengerId',
          isEqualTo: passengerId,
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs
            .map(
              Booking.fromFirestore,
            )
            .toList();
      },
    );
  }

  //==========================================================================
  // Driver Trip History
  //==========================================================================

  Stream<List<Booking>>
      bookingsForDriver(
    String driverId,
  ) {
    return _collection
        .where(
          'driverId',
          isEqualTo: driverId,
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs
            .map(
              Booking.fromFirestore,
            )
            .toList();
      },
    );
  }

  //==========================================================================
  // Update Booking
  //==========================================================================

  Future<void> updateBooking(
    Booking booking,
  ) async {
    await _collection
        .doc(
          booking.bookingId,
        )
        .update(
          booking.toFirestore(),
        );
  }

  //==========================================================================
  // Update Status
  //==========================================================================

  Future<void> updateStatus({
    required String bookingId,
    required BookingStatus status,
  }) async {
    await _collection
        .doc(
          bookingId,
        )
        .update({
      'status': status.name,
      'updatedAt':
          FieldValue.serverTimestamp(),
    });
  }

  //==========================================================================
  // Assign Driver
  //==========================================================================

  Future<void> assignDriver({
    required String bookingId,
    required String driverId,
  }) async {
    await _collection
        .doc(
          bookingId,
        )
        .update({
      'driverId': driverId,
      'status':
          BookingStatus
              .driverAssigned
              .name,
      'updatedAt':
          FieldValue.serverTimestamp(),
    });
  }

  //==========================================================================
  // Cancel Booking
  //==========================================================================

  Future<void> cancelBooking(
    String bookingId,
  ) async {
    await updateStatus(
      bookingId: bookingId,
      status:
          BookingStatus.cancelled,
    );
  }

  //==========================================================================
  // Complete Booking
  //==========================================================================

  Future<void> completeBooking(
    String bookingId,
  ) async {
    await updateStatus(
      bookingId: bookingId,
      status:
          BookingStatus.completed,
    );
  }

  //==========================================================================
  // Delete Booking
  //==========================================================================

  Future<void> deleteBooking(
    String bookingId,
  ) async {
    await _collection
        .doc(
          bookingId,
        )
        .delete();
  }
}