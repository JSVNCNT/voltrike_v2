import '../models/driver_rating.dart';
import '../services/firestore_service.dart';

/// ===========================================================================
/// Driver Rating Repository
///
/// Firestore:
/// ratings/{ratingId}
/// ===========================================================================
class DriverRatingRepository {
  DriverRatingRepository({
    FirestoreService? firestoreService,
  }) : _firestoreService =
            firestoreService ??
            FirestoreService.instance;

  final FirestoreService _firestoreService;

  static const String _collection =
      'ratings';

  //==========================================================================
  // Create Rating
  //==========================================================================

  Future<void> createRating(
    DriverRating rating,
  ) {
    return _firestoreService.setDocument(
      collection: _collection,
      documentId: rating.ratingId,
      data: rating.toFirestore(),
    );
  }

  //==========================================================================
  // Delete Rating
  //==========================================================================

  Future<void> deleteRating(
    String ratingId,
  ) {
    return _firestoreService.deleteDocument(
      collection: _collection,
      documentId: ratingId,
    );
  }

  //==========================================================================
  // Get Rating
  //==========================================================================

  Future<DriverRating?> getRating(
    String ratingId,
  ) async {
    final snapshot =
        await _firestoreService.getDocument(
      _collection,
      ratingId,
    );

    if (!snapshot.exists) {
      return null;
    }

    return DriverRating.fromFirestore(
      snapshot,
    );
  }

  /// New ratings use a deterministic ID, allowing a direct read that remains
  /// compatible with member-only Firestore rules and avoids a collection scan.
  Future<bool> hasRatingForBooking({
    required String bookingId,
    required String passengerId,
  }) async {
    final snapshot = await _firestoreService.firestore
        .collection(_collection)
        .doc('${bookingId}_$passengerId')
        .get();
    return snapshot.exists;
  }

  //==========================================================================
  // Driver Ratings Stream
  //==========================================================================

  Stream<List<DriverRating>>
      driverRatings(
    String driverId,
  ) {
    return _firestoreService.firestore
        .collection(_collection)
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
          (snapshot) => snapshot.docs
              .map(
                DriverRating.fromFirestore,
              )
              .toList(),
        );
  }

  //==========================================================================
  // Passenger Ratings Stream
  //==========================================================================

  Stream<List<DriverRating>>
      passengerRatings(
    String passengerId,
  ) {
    return _firestoreService.firestore
        .collection(_collection)
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
          (snapshot) => snapshot.docs
              .map(
                DriverRating.fromFirestore,
              )
              .toList(),
        );
  }

  //==========================================================================
  // Average Rating
  //==========================================================================

  Future<double> getAverageRating(
    String driverId,
  ) async {
    final snapshot =
        await _firestoreService.firestore
            .collection(_collection)
            .where(
              'driverId',
              isEqualTo: driverId,
            )
            .get();

    if (snapshot.docs.isEmpty) {
      return 0;
    }

    double total = 0;

    for (final doc in snapshot.docs) {
      total +=
          (doc.data()['rating'] as num)
              .toDouble();
    }

    return total /
        snapshot.docs.length;
  }
}
