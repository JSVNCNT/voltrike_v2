import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/booking.dart';
import '../models/driver_booking_offer.dart';
import '../models/model_date_parser.dart';
import '../models/route_policy_advisory.dart';
import '../../core/services/voltrike_api.dart';
import '../../core/services/durable_command_outbox.dart';

class BookingCreationResult {
  const BookingCreationResult({
    required this.bookingId,
    required this.distanceMeters,
    required this.estimatedFare,
    required this.isOutsideToda,
    required this.fareBreakdown,
    this.fareVersion = 0,
    this.fareSnapshot = const <String, dynamic>{},
    this.authoritativeRoutePolyline = '',
    this.searchExpiresAt,
    this.avoidedRouteRestrictionNames = const [],
    this.routePolicyVersion = 0,
    this.routePolicy = const RoutePolicyAdvisory(),
  });

  final String bookingId;
  final int distanceMeters;
  final double estimatedFare;
  final bool isOutsideToda;
  final Map<String, dynamic> fareBreakdown;
  final int fareVersion;
  final Map<String, dynamic> fareSnapshot;
  final String authoritativeRoutePolyline;
  final DateTime? searchExpiresAt;
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
      fareVersion: _intValue(data['fareVersion']) ?? fallback.fareVersion,
      fareSnapshot: _stringKeyedMap(data['fareSnapshot']),
      authoritativeRoutePolyline:
          _stringValue(data['authoritativeRoutePolyline']) ??
          fallback.authoritativeRoutePolyline,
      searchExpiresAt:
          parseModelDate(data['searchExpiresAt']) ?? fallback.searchExpiresAt,
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

  factory BookingCreationResult.fromBooking(Booking booking) {
    return BookingCreationResult(
      bookingId: booking.bookingId,
      distanceMeters: booking.distanceMeters,
      estimatedFare: booking.estimatedFare,
      isOutsideToda: booking.isOutsideToda,
      fareBreakdown: booking.fareBreakdown,
      fareVersion: booking.fareVersion,
      fareSnapshot: booking.fareSnapshot,
      authoritativeRoutePolyline: booking.authoritativeRoutePolyline,
      searchExpiresAt: booking.searchExpiresAt,
      avoidedRouteRestrictionNames: booking.routePolicy.avoidedRestrictionNames,
      routePolicyVersion: booking.routePolicyVersion,
      routePolicy: booking.routePolicy,
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
    VoltrikeApi? api,
    DurableCommandOutbox? outbox,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _api = api ?? VoltrikeApi.instance,
       _outbox = outbox ?? DurableCommandOutbox.instance {
    _startOutboxReplayOnce(_outbox);
  }

  static Future<void>? _outboxReplay;

  static void _startOutboxReplayOnce(DurableCommandOutbox outbox) {
    _outboxReplay ??= outbox.replayForCurrentUser().whenComplete(() {
      _outboxReplay = null;
    });
    unawaited(_outboxReplay);
  }

  final FirebaseFirestore _firestore;
  final VoltrikeApi _api;
  final DurableCommandOutbox _outbox;
  final Uuid _uuid = const Uuid();
  static const int _maximumRetainedOperationIds = 32;
  static const Duration _operationIdRetention = Duration(minutes: 10);
  final Map<String, _RetainedOperationId> _operationIds =
      <String, _RetainedOperationId>{};
  final Map<String, Future<void>> _inFlightVoidOperations =
      <String, Future<void>>{};
  final Map<String, Future<BookingCreationResult>> _inFlightCreations =
      <String, Future<BookingCreationResult>>{};

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('bookings');

  //==========================================================================
  // Create Booking
  //==========================================================================

  Future<BookingCreationResult> createBooking(
    Booking booking, {
    String goQuoteToken = '',
  }) async {
    final key = 'create:${booking.bookingId}';
    final existing = _inFlightCreations[key];
    if (existing != null) return existing;

    final operationId = _operationIdFor(key);
    final future = _createBooking(booking, operationId, goQuoteToken);
    _inFlightCreations[key] = future;
    try {
      final result = await future;
      _operationIds.remove(key);
      return result;
    } finally {
      if (identical(_inFlightCreations[key], future)) {
        _inFlightCreations.remove(key);
      }
    }
  }

  Future<BookingCreationResult> _createBooking(
    Booking booking,
    String operationId,
    String goQuoteToken,
  ) async {
    final payload = <String, dynamic>{
      'bookingId': booking.bookingId,
      'commandId': operationId,
      'pickup': {
        'latitude': booking.pickup.latitude,
        'longitude': booking.pickup.longitude,
      },
      'destination': {
        'latitude': booking.destination.latitude,
        'longitude': booking.destination.longitude,
      },
      'pickupName': booking.pickupName,
      'destinationName': booking.destinationName,
      'pickupAddress': booking.pickupAddress,
      'destinationAddress': booking.destinationAddress,
      'additionalPassengers': booking.additionalPassengers,
      'baggageCount': booking.baggageCount,
      'quoteToken': goQuoteToken,
    };
    final outboxKey = 'booking.create:${booking.bookingId}';
    await _outbox.enqueue(
      key: outboxKey,
      kind: 'booking.create',
      payload: payload,
    );
    final response = await _api.createBooking(payload);
    await _outbox.complete(outboxKey);
    return BookingCreationResult.fromCallable(response, fallback: booking);
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
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  //==========================================================================
  // Watch Driver Bookings
  //==========================================================================

  Stream<List<Booking>> watchDriverBookings(String driverId) {
    return _collection
        .where('driverId', isEqualTo: driverId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(Booking.fromFirestore).toList();
        });
  }

  //==========================================================================
  // Watch Passenger Bookings
  //==========================================================================

  Stream<List<Booking>> watchPassengerBookings(String passengerId) {
    return _collection
        .where('passengerId', isEqualTo: passengerId)
        .limit(100)
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
        .limit(100)
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
        .limit(50)
        .snapshots()
        .asyncMap((snapshot) async {
          final offers =
              snapshot.docs
                  .map(DriverBookingOffer.fromFirestore)
                  .where((offer) => !offer.isExpired)
                  .toList()
                ..sort(DriverBookingOffer.compareForDisplay);
          final bookings = await Future.wait(
            offers.map(
              (offer) => Future.value(
                offer.toBooking() ?? getBooking(offer.bookingId),
              ),
            ),
          );
          return bookings
              .whereType<Booking>()
              .where((booking) => booking.status == BookingStatus.pending)
              .toList();
        });
  }

  /// Watches the passenger's single active booking, if one exists.
  ///
  /// The lifecycle backend maintains one lightweight pointer per passenger.
  /// Following it avoids downloading and sorting the passenger's entire
  /// booking history whenever the active ride changes.
  Stream<Booking?> activeBookingForPassenger(String passengerId) {
    final pointer = _firestore
        .collection('activePassengerBookings')
        .doc(passengerId);
    return Stream<Booking?>.multi((controller) {
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      bookingSubscription;
      var generation = 0;

      Future<void> followPointer(
        DocumentSnapshot<Map<String, dynamic>> snapshot,
      ) async {
        final localGeneration = ++generation;
        await bookingSubscription?.cancel();
        bookingSubscription = null;
        if (localGeneration != generation) return;

        final bookingId = _stringValue(snapshot.data()?['bookingId']);
        if (bookingId == null) {
          controller.add(null);
          return;
        }
        bookingSubscription = _collection.doc(bookingId).snapshots().listen((
          bookingSnapshot,
        ) {
          if (!bookingSnapshot.exists) {
            controller.add(null);
            return;
          }
          try {
            final booking = Booking.fromFirestore(bookingSnapshot);
            final isTerminal =
                booking.status == BookingStatus.completed ||
                booking.status == BookingStatus.cancelled;
            controller.add(isTerminal ? null : booking);
          } catch (error, stackTrace) {
            controller.addError(error, stackTrace);
          }
        }, onError: controller.addError);
      }

      final pointerSubscription = pointer.snapshots().listen((snapshot) async {
        try {
          await followPointer(snapshot);
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
        }
      }, onError: controller.addError);
      controller.onCancel = () async {
        generation++;
        await pointerSubscription.cancel();
        await bookingSubscription?.cancel();
      };
    });
  }

  /// Loads the passenger's active booking once during application startup.
  ///
  /// This deliberately reuses the same selection rule as the live listener so
  /// a cold start and a running session cannot restore different rides.
  Future<Booking?> getActiveBookingForPassenger(String passengerId) {
    return _firestore
        .collection('activePassengerBookings')
        .doc(passengerId)
        .get()
        .then((pointer) async {
          final bookingId = _stringValue(pointer.data()?['bookingId']);
          if (bookingId == null) return null;
          final booking = await getBooking(bookingId);
          if (booking == null ||
              booking.status == BookingStatus.completed ||
              booking.status == BookingStatus.cancelled) {
            return null;
          }
          return booking;
        });
  }

  //==========================================================================
  // Driver Trip History
  //==========================================================================

  Stream<List<Booking>> bookingsForDriver(String driverId) {
    return _collection
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .limit(100)
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

  Future<void> assignDriver({required String bookingId}) async {
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

  /// The driver's cash swipe is intentionally a single durable operation:
  /// record receipt and close the trip on the server.
  Future<void> confirmCashReceived(String bookingId) async {
    await _transition(bookingId: bookingId, action: 'payment');
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
  Future<void> acceptBookingTransaction({required String bookingId}) {
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
    await _runVoidOperation('decline:$bookingId', (operationId) async {
      await _sendDurableTransition(bookingId, 'decline', {
        'commandId': operationId,
        'action': 'decline',
        'expectedRevision': await _expectedRevision(bookingId),
      });
    });
  }

  Future<void> confirmCashPayment({
    required String bookingId,
    required bool received,
  }) async {
    await _transition(
      bookingId: bookingId,
      action: received ? 'payment' : 'payment',
    );
  }

  Future<void> disputeSettlement({
    required String bookingId,
    required String reason,
  }) async {
    await _runVoidOperation('dispute:$bookingId', (operationId) async {
      await _sendDurableTransition(bookingId, 'dispute', {
        'commandId': operationId,
        'action': 'dispute',
        'reasonDetail': reason,
        'expectedRevision': await _expectedRevision(bookingId),
      });
    });
  }

  Future<void> acknowledgeDriverReceipt({required String bookingId}) async {
    await _runVoidOperation('receipt:$bookingId', (operationId) async {
      await _sendDurableTransition(bookingId, 'receipt', {
        'commandId': operationId,
        'action': 'receipt',
        'expectedRevision': await _expectedRevision(bookingId),
      });
    });
  }

  Future<void> _accept(String bookingId) async {
    await _runVoidOperation('accept:$bookingId', (operationId) async {
      await _sendDurableTransition(bookingId, 'accept', {
        'commandId': operationId,
        'action': 'accept',
        'expectedRevision': await _expectedRevision(bookingId),
      });
    });
  }

  Future<void> _transition({
    required String bookingId,
    required String action,
    String? reasonCode,
    String? reasonDetail,
  }) async {
    await _runVoidOperation('$action:$bookingId', (operationId) async {
      await _sendDurableTransition(bookingId, action, {
        'commandId': operationId,
        'action': action,
        'expectedRevision': await _expectedRevision(bookingId),
        'reasonCode': ?reasonCode,
        'reasonDetail': ?reasonDetail,
      });
    });
  }

  Future<void> _sendDurableTransition(
    String bookingId,
    String action,
    Map<String, dynamic> command,
  ) async {
    final outboxKey = 'booking.transition:$action:$bookingId';
    await _outbox.enqueue(
      key: outboxKey,
      kind: 'booking.transition',
      payload: <String, dynamic>{'bookingId': bookingId, 'command': command},
    );
    await _api.transitionBooking(bookingId, command);
    await _outbox.complete(outboxKey);
  }

  Future<int> _expectedRevision(String bookingId) async {
    final snapshot = await _collection.doc(bookingId).get();
    final value = snapshot.data()?['revision'];
    return value is num ? value.toInt() : 1;
  }

  Future<void> _runVoidOperation(
    String key,
    Future<void> Function(String operationId) operation,
  ) async {
    final existing = _inFlightVoidOperations[key];
    if (existing != null) return existing;

    final operationId = _operationIdFor(key);
    final future = operation(operationId);
    _inFlightVoidOperations[key] = future;
    try {
      await future;
      _operationIds.remove(key);
    } finally {
      if (identical(_inFlightVoidOperations[key], future)) {
        _inFlightVoidOperations.remove(key);
      }
    }
  }

  String _operationIdFor(String key) {
    final now = DateTime.now();
    _operationIds.removeWhere(
      (_, operation) =>
          now.difference(operation.retainedAt) > _operationIdRetention,
    );
    while (_operationIds.length >= _maximumRetainedOperationIds &&
        !_operationIds.containsKey(key)) {
      _operationIds.remove(_operationIds.keys.first);
    }
    return (_operationIds[key] ??= _RetainedOperationId(
      value: _uuid.v4(),
      retainedAt: now,
    )).value;
  }

  String _actionForStatus(BookingStatus status) {
    switch (status) {
      case BookingStatus.driverArriving:
        return 'arrived';
      case BookingStatus.passengerOnBoard:
        return 'start';
      case BookingStatus.paymentConfirmation:
        return 'payment';
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

class _RetainedOperationId {
  const _RetainedOperationId({required this.value, required this.retainedAt});

  final String value;
  final DateTime retainedAt;
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
