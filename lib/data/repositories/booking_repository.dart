import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/booking.dart';
import '../models/driver_booking_offer.dart';
import '../models/route_policy_advisory.dart';

class BookingCreationResult {
  const BookingCreationResult({
    required this.bookingId,
    required this.distanceMeters,
    required this.estimatedFare,
    required this.isOutsideToda,
    required this.fareBreakdown,
    this.avoidedRouteRestrictionNames = const [],
    this.routePolicyVersion = 0,
    this.routePolicy = const RoutePolicyAdvisory(),
  });

  final String bookingId;
  final int distanceMeters;
  final double estimatedFare;
  final bool isOutsideToda;
  final Map<String, dynamic> fareBreakdown;
  final List<String> avoidedRouteRestrictionNames;
  final int routePolicyVersion;
  final RoutePolicyAdvisory routePolicy;

  factory BookingCreationResult.fromCallable(
    Object? value, {
    required Booking fallback,
  }) {
    final data = _stringKeyedMap(value);
    return BookingCreationResult(
      bookingId: _stringValue(data['bookingId']) ?? fallback.bookingId,
      distanceMeters:
          _intValue(data['distanceMeters']) ?? fallback.distanceMeters,
      estimatedFare:
          _doubleValue(data['estimatedFare']) ?? fallback.estimatedFare,
      isOutsideToda: data['isOutsideToda'] is bool
          ? data['isOutsideToda'] as bool
          : fallback.isOutsideToda,
      fareBreakdown: _stringKeyedMap(data['fareBreakdown']),
      avoidedRouteRestrictionNames: _stringList(
        data['avoidedRouteRestrictionNames'],
      ),
      routePolicyVersion: _intValue(data['routePolicyVersion']) ?? 0,
      routePolicy:
          RoutePolicyAdvisory.fromMap(
            data['highwayRouteAdvisory'] ?? data['routeAdvisory'],
          ).copyWith(
            avoidedRestrictionNames: _stringList(
              data['avoidedRouteRestrictionNames'],
            ),
          ),
    );
  }
}

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
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('bookings');

  //==========================================================================
  // Create Booking
  //==========================================================================

  Future<BookingCreationResult> createBooking(Booking booking) async {
    final response = await _functions
        .httpsCallable('createBookingLifecycle')
        .call({
          'bookingId': booking.bookingId,
          'operationId': _uuid.v4(),
          'pickup': {
            'latitude': booking.pickup.latitude,
            'longitude': booking.pickup.longitude,
          },
          'destination': {
            'latitude': booking.destination.latitude,
            'longitude': booking.destination.longitude,
          },
          'pickupAddress': booking.pickupAddress,
          'destinationAddress': booking.destinationAddress,
          'distanceMeters': booking.distanceMeters,
          'estimatedFare': booking.estimatedFare,
          'additionalPassengers': booking.additionalPassengers,
          'baggageCount': booking.baggageCount,
          'isOutsideToda': booking.isOutsideToda,
          'clientRouteAdvisory': booking.routePolicy.toMap(),
        });
    return BookingCreationResult.fromCallable(response.data, fallback: booking);
  }

  //==========================================================================
  // Get Booking
  //==========================================================================

  Future<Booking?> getBooking(String bookingId) async {
    final doc = await _collection.doc(bookingId).get();

    if (!doc.exists) {
      return null;
    }

    return Booking.fromFirestore(doc);
  }

  //==========================================================================
  // Watch Booking
  //==========================================================================

  Stream<Booking?> watchBooking(String bookingId) {
    return _collection.doc(bookingId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }

      return Booking.fromFirestore(doc);
    });
  }

  //==========================================================================
  // Watch Pending Bookings
  //==========================================================================

  Stream<List<Booking>> watchPendingBookings() {
    return _collection
        .where('status', isEqualTo: BookingStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  //==========================================================================
  // Watch Driver Bookings
  //==========================================================================

  Stream<List<Booking>> watchDriverBookings(String driverId) {
    return _collection.where('driverId', isEqualTo: driverId).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map(Booking.fromFirestore).toList();
    });
  }

  //==========================================================================
  // Watch Passenger Bookings
  //==========================================================================

  Stream<List<Booking>> watchPassengerBookings(String passengerId) {
    return _collection
        .where('passengerId', isEqualTo: passengerId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  //==========================================================================
  // Passenger Trip History
  //==========================================================================

  Stream<List<Booking>> bookingsForPassenger(String passengerId) {
    return _collection
        .where('passengerId', isEqualTo: passengerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  /// Watches only offers explicitly dispatched to one driver.
  Stream<List<Booking>> watchDriverOffers(String driverId) {
    return _firestore
        .collection('drivers')
        .doc(driverId)
        .collection('bookingOffers')
        .where('status', isEqualTo: 'offered')
        .snapshots()
        .asyncMap((snapshot) async {
          final offers =
              snapshot.docs
                  .map(DriverBookingOffer.fromFirestore)
                  .where((offer) => !offer.isExpired)
                  .toList()
                ..sort(DriverBookingOffer.compareForDisplay);
          final bookings = await Future.wait(
            offers.map((offer) => getBooking(offer.bookingId)),
          );
          return bookings
              .whereType<Booking>()
              .where((booking) => booking.status == BookingStatus.pending)
              .toList();
        });
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
      }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

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

  Stream<List<Booking>> bookingsForDriver(String driverId) {
    return _collection
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  //==========================================================================
  // Update Booking
  //==========================================================================

  Future<void> updateBooking(Booking booking) async {
    throw UnsupportedError(
      'Generic booking updates are disabled. Use an authoritative lifecycle operation.',
    );
  }

  //==========================================================================
  // Update Status
  //==========================================================================

  Future<void> updateStatus({
    required String bookingId,
    required BookingStatus status,
  }) async {
    await _transition(bookingId: bookingId, action: _actionForStatus(status));
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
    await _accept(bookingId);
  }

  //==========================================================================
  // Cancel Booking
  //==========================================================================

  Future<void> cancelBooking(
    String bookingId, {
    Set<BookingStatus> allowedCurrentStatuses = const {
      BookingStatus.pending,
      BookingStatus.driverAssigned,
      BookingStatus.driverArriving,
    },
    String reasonCode = 'cancelled_by_user',
    String? reasonDetail,
  }) {
    return _transition(
      bookingId: bookingId,
      action: 'cancel',
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
  }

  //==========================================================================
  // Complete Booking
  //==========================================================================

  Future<void> completeBooking(String bookingId) async {
    await _transition(bookingId: bookingId, action: 'complete');
  }

  /// Atomically advances a booking only from an allowed current state.
  Future<void> transitionStatus({
    required String bookingId,
    required Set<BookingStatus> allowedCurrentStatuses,
    required BookingStatus nextStatus,
  }) {
    return _transition(
      bookingId: bookingId,
      action: _actionForStatus(nextStatus),
    );
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
    return _accept(bookingId);
  }

  //==========================================================================
  // Delete Booking
  //==========================================================================

  Future<void> deleteBooking(String bookingId) async {
    throw UnsupportedError(
      'Bookings are retained as an immutable audit record.',
    );
  }

  Future<void> markNoShow({required String bookingId}) {
    return _transition(bookingId: bookingId, action: 'noShow');
  }

  Future<void> declineBookingOffer({required String bookingId}) async {
    await _functions.httpsCallable('declineBookingOfferLifecycle').call<void>({
      'bookingId': bookingId,
      'operationId': _uuid.v4(),
    });
  }

  Future<void> confirmCashPayment({
    required String bookingId,
    required bool received,
  }) async {
    await _functions.httpsCallable('confirmCashPayment').call<void>({
      'bookingId': bookingId,
      'operationId': _uuid.v4(),
      'confirmation': received ? 'received' : 'paid',
    });
  }

  Future<void> disputeSettlement({
    required String bookingId,
    required String reason,
  }) async {
    await _functions.httpsCallable('submitSettlementDispute').call<void>({
      'bookingId': bookingId,
      'reason': reason,
    });
  }

  Future<void> acknowledgeDriverReceipt({required String bookingId}) async {
    await _functions.httpsCallable('acknowledgeDriverReceipt').call<void>({
      'bookingId': bookingId,
    });
  }

  Future<void> _accept(String bookingId) async {
    await _functions.httpsCallable('acceptBookingLifecycle').call({
      'bookingId': bookingId,
      'operationId': _uuid.v4(),
    });
  }

  Future<void> _transition({
    required String bookingId,
    required String action,
    String? reasonCode,
    String? reasonDetail,
  }) async {
    await _functions.httpsCallable('transitionBookingLifecycle').call({
      'bookingId': bookingId,
      'operationId': _uuid.v4(),
      'action': action,
      'reasonCode': ?reasonCode,
      'reasonDetail': ?reasonDetail,
    });
  }

  String _actionForStatus(BookingStatus status) {
    switch (status) {
      case BookingStatus.driverArriving:
        return 'arrived';
      case BookingStatus.passengerOnBoard:
        return 'start';
      case BookingStatus.paymentConfirmation:
        return 'dropOff';
      case BookingStatus.completed:
        return 'complete';
      case BookingStatus.cancelled:
        return 'cancel';
      case BookingStatus.pending:
      case BookingStatus.driverAssigned:
        throw UnsupportedError(
          'Status ${status.name} requires a dedicated lifecycle operation.',
        );
    }
  }
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String? _stringValue(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

int? _intValue(Object? value) {
  if (value is num && value.isFinite) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return List<String>.unmodifiable(
    value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet(),
  );
}
