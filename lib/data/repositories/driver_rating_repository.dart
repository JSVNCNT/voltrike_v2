import 'package:cloud_functions/cloud_functions.dart';

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
    FirebaseFunctions? functions,
  }) : _firestoreService = firestoreService ?? FirestoreService.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirestoreService _firestoreService;
  final FirebaseFunctions _functions;

  static const String _collection = 'ratings';

  //==========================================================================
  // Create Rating
  //==========================================================================

  Future<void> createRating(DriverRating rating) async {
    await _functions.httpsCallable('submitDriverRating').call<void>({
      'bookingId': rating.bookingId,
      'rating': rating.rating,
      'comment': rating.comment,
    });
  }

  //==========================================================================
  // Delete Rating
  //==========================================================================

  Future<void> deleteRating(String ratingId) {
    throw UnsupportedError('Ratings are retained as an immutable trip record.');
  }

  //==========================================================================
  // Get Rating
  //==========================================================================

  Future<DriverRating?> getRating(String ratingId) async {
    final snapshot = await _firestoreService.getDocument(_collection, ratingId);

    if (!snapshot.exists) {
      return null;
    }

    return DriverRating.fromFirestore(snapshot);
  }

  /// New ratings use a deterministic ID, allowing a direct read that remains
  /// compatible with member-only Firestore rules and avoids a collection scan.
  Future<bool> hasRatingForBooking({
    required String bookingId,
    required String passengerId,
  }) async {
    return await getRatingForBooking(
          bookingId: bookingId,
          passengerId: passengerId,
        ) !=
        null;
  }

  Future<DriverRating?> getRatingForBooking({
    required String bookingId,
    required String passengerId,
  }) async {
    final snapshot = await _firestoreService.firestore
        .collection(_collection)
        .where('passengerId', isEqualTo: passengerId)
        .get();
    for (final document in snapshot.docs) {
      if (document.data()['bookingId'] == bookingId) {
        return DriverRating.fromFirestore(document);
      }
    }
    return null;
  }

  //==========================================================================
  // Driver Ratings Stream
  //==========================================================================

  Stream<List<DriverRating>> driverRatings(String driverId) {
    return _firestoreService.firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
          final ratings = snapshot.docs
              .map(DriverRating.fromFirestore)
              .toList();
          ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ratings;
        });
  }

  //==========================================================================
  // Passenger Ratings Stream
  //==========================================================================

  Stream<List<DriverRating>> passengerRatings(String passengerId) {
    return _firestoreService.firestore
        .collection(_collection)
        .where('passengerId', isEqualTo: passengerId)
        .snapshots()
        .map((snapshot) {
          final ratings = snapshot.docs
              .map(DriverRating.fromFirestore)
              .toList();
          ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ratings;
        });
  }

  //==========================================================================
  // Average Rating
  //==========================================================================

  Future<double> getAverageRating(String driverId) async {
    final snapshot = await _firestoreService.firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .get();

    if (snapshot.docs.isEmpty) {
      return 0;
    }

    double total = 0;

    for (final doc in snapshot.docs) {
      total += (doc.data()['rating'] as num).toDouble();
    }

    return total / snapshot.docs.length;
  }
}
