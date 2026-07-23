import 'package:cloud_firestore/cloud_firestore.dart';

/// ===========================================================================
/// Trip Status
/// ===========================================================================
enum TripStatus {
  waitingDriver,
  driverArriving,
  driverArrived,
  inProgress,
  completed,
  cancelled,
}

/// ===========================================================================
/// Trip Model
/// ===========================================================================
class Trip {
  const Trip({
    required this.tripId,
    required this.bookingId,
    required this.driverId,
    required this.passengerId,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  final String tripId;

  final String bookingId;

  final String driverId;

  final String passengerId;

  final TripStatus status;

  final DateTime startedAt;

  final DateTime? completedAt;

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'bookingId': bookingId,
      'driverId': driverId,
      'passengerId': passengerId,
      'status': status.name,
      'startedAt': Timestamp.fromDate(
        startedAt,
      ),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(
              completedAt!,
            ),
    };
  }
}

/// ===========================================================================
/// Trip Service
///
/// Handles active passenger trips.
///
/// Future:
/// • Live driver tracking
/// • ETA updates
/// • Driver location
/// • Trip completion
/// • Receipt generation
/// ===========================================================================
class TripService {
  TripService._();

  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>
      get _trips =>
          _firestore.collection('trips');

  /// =========================================================================
  /// Create Trip
  /// =========================================================================

  static Future<void> createTrip(
    Trip trip,
  ) async {
    await _trips
        .doc(trip.tripId)
        .set(
          trip.toMap(),
        );
  }

  /// =========================================================================
  /// Update Status
  /// =========================================================================

  static Future<void> updateStatus({
    required String tripId,
    required TripStatus status,
  }) async {
    await _trips.doc(tripId).update({
      'status': status.name,
    });
  }

  /// =========================================================================
  /// Complete Trip
  /// =========================================================================

  static Future<void> completeTrip(
    String tripId,
  ) async {
    await _trips.doc(tripId).update({
      'status': TripStatus.completed.name,
      'completedAt':
          Timestamp.fromDate(
        DateTime.now(),
      ),
    });
  }

  /// =========================================================================
  /// Cancel Trip
  /// =========================================================================

  static Future<void> cancelTrip(
    String tripId,
  ) async {
    await updateStatus(
      tripId: tripId,
      status: TripStatus.cancelled,
    );
  }

  /// =========================================================================
  /// Trip Stream
  /// =========================================================================

  static Stream<DocumentSnapshot<Map<String, dynamic>>>
      tripStream(
    String tripId,
  ) {
    return _trips.doc(tripId).snapshots();
  }
}    