import '../../core/services/voltrike_api.dart';
import '../models/driver_rating.dart';
import '../services/firestore_service.dart';

/// ===========================================================================
/// Driver Rating Repository
///
/// Firestore:
/// ratings/{ratingId}
/// ===========================================================================
class DriverRatingRepository {
  DriverRatingRepository({FirestoreService? firestoreService, VoltrikeApi? api})
    : _firestoreService = firestoreService ?? FirestoreService.instance,
      _api = api ?? VoltrikeApi.instance;

  final FirestoreService _firestoreService;
  final VoltrikeApi _api;

  static const String _collection = 'ratings';

  //==========================================================================
  // Create Rating
  //==========================================================================

  Future<void> createRating(DriverRating rating) async {
    await _api.operation('submitDriverRating', {
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
    return getRating('${bookingId}_$passengerId');
  }

  //==========================================================================
  // Driver Ratings Stream
  //==========================================================================

  Stream<List<DriverRating>> driverRatings(String driverId) {
    return _firestoreService.firestore
        .collection(_collection)
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .limit(3)
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
