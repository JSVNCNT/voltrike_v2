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

  /// Watches the passenger's single active booking, if one exists.
  ///
  /// Status filtering is performed in memory to avoid requiring a compound
  /// Firestore index during the current migration. The result is deterministic
  /// when legacy data contains more than one active record.
  Stream<Booking?> activeBookingForPassenger(String passengerId) {
    return watchPassengerBookings(passengerId).map((bookings) {
      final active = bookings.where((booking) {
        return booking.status != BookingStatus.completed &&
            booking.status != BookingStatus.cancelled;
      }).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return active.isEmpty ? null : active.first;
    });
  }

  /// Loads the passenger's active booking once during application startup.
  ///
  /// This deliberately reuses the same selection rule as the live listener so
  /// a cold start and a running session cannot restore different rides.
  Future<Booking?> getActiveBookingForPassenger(String passengerId) {
    return activeBookingForPassenger(passengerId).first;
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

    //======================================================================
    // Driver
    //======================================================================

    required String driverId,

    //======================================================================
    // Driver Snapshot
    //======================================================================

    required String driverName,
    required String driverPhotoUrl,
    required double driverRating,
    required String vehicleNumber,
    required String plateNumber,
    required String todaName,
  }) async {
    await _collection
        .doc(
          bookingId,
        )
        .update({
      //====================================================================
      // Driver
      //====================================================================

      'driverId': driverId,

      //====================================================================
      // Driver Snapshot
      //====================================================================

      'driverName': driverName,
      'driverPhotoUrl': driverPhotoUrl,
      'driverRating': driverRating,
      'vehicleNumber': vehicleNumber,
      'plateNumber': plateNumber,
      'todaName': todaName,

      //====================================================================
      // Booking Status
      //====================================================================

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
    await _collection.doc(bookingId).update({
      'status': BookingStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Atomically reserves a pending booking for one available driver.
  ///
  /// Both booking assignment and driver availability are updated in the same
  /// transaction, preventing two drivers from accepting the same request.
  Future<void> acceptBookingTransaction({
    required String bookingId,
    required String driverId,
    required String driverName,
    required String driverPhotoUrl,
    required double driverRating,
    required String vehicleNumber,
    required String plateNumber,
    required String todaName,
  }) {
    final bookingRef = _collection.doc(bookingId);
    final driverRef = _firestore.collection('drivers').doc(driverId);

    return _firestore.runTransaction((transaction) async {
      final bookingSnapshot = await transaction.get(bookingRef);
      final driverSnapshot = await transaction.get(driverRef);

      if (!bookingSnapshot.exists || !driverSnapshot.exists) {
        throw StateError('Booking or driver record no longer exists.');
      }

      final bookingData = bookingSnapshot.data()!;
      final driverData = driverSnapshot.data()!;
      if (bookingData['status'] != BookingStatus.pending.name ||
          bookingData['driverId'] != null) {
        throw StateError('This booking has already been accepted.');
      }

      if (driverData['isOnline'] != true ||
          driverData['isAvailable'] != true ||
          driverData['currentBookingId'] != null) {
        throw StateError('You are not available for a new booking.');
      }

      transaction.update(bookingRef, {
        'driverId': driverId,
        'driverName': driverName,
        'driverPhotoUrl': driverPhotoUrl,
        'driverRating': driverRating,
        'vehicleNumber': vehicleNumber,
        'plateNumber': plateNumber,
        'todaName': todaName,
        'status': BookingStatus.driverAssigned.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(driverRef, {
        'currentBookingId': bookingId,
        'isAvailable': false,
      });
    });
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
