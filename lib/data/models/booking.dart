import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'model_date_parser.dart';
import 'route_policy_advisory.dart';

/// ===========================================================================
/// Booking Status
///
/// Represents the lifecycle of a booking stored in Firestore.
///
/// Flow:
/// pending
/// → driverAssigned
/// → driverArriving
/// → passengerOnBoard
/// → completed
///
/// or
///
/// pending
/// → cancelled
///
/// UI-only states (such as estimating fare or searching for a driver)
/// should not be stored in Firestore.
/// ===========================================================================
enum BookingStatus {
  pending,
  driverAssigned,
  driverArriving,
  passengerOnBoard,
  paymentConfirmation,
  completed,
  cancelled,
}

/// ===========================================================================
/// Booking Model
///
/// Represents a ride booking stored in Firestore.
///
/// Firestore Collection:
/// bookings/{bookingId}
/// ===========================================================================
class Booking {
  static const int currentSchemaVersion = 2;

  const Booking({
    this.schemaVersion = currentSchemaVersion,
    required this.bookingId,
    required this.passengerId,
    this.passengerName,
    this.passengerPhone,
    this.passengerPhotoUrl,
    this.driverId,

    //======================================================================
    // Driver Snapshot
    //======================================================================
    this.driverName,
    this.driverPhotoUrl,
    this.driverRating,
    this.vehicleNumber,
    this.plateNumber,
    this.todaId,
    this.todaName,

    required this.pickup,
    required this.destination,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceMeters,
    required this.estimatedFare,
    this.authoritativeRoutePolyline = '',
    this.fareVersion = 0,
    this.fareSnapshot = const <String, dynamic>{},
    this.fareBreakdown = const <String, dynamic>{},
    this.searchExpiresAt,
    this.paymentMethod = 'cash',
    double? amountDue,
    double? grossFare,
    this.commissionPercent = 0,
    this.commissionAmount = 0,
    double? driverNetEarnings,
    this.passengerPaidAt,
    this.driverReceivedAt,
    this.settlementStatus = 'awaiting_confirmation',
    this.receiptNumber,
    required this.additionalPassengers,
    required this.baggageCount,
    required this.isOutsideToda,
    this.routePolicyVersion = 0,
    this.routePolicy = const RoutePolicyAdvisory(),
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.assignedAt,
    this.arrivedAt,
    this.pickupConfirmedAt,
    this.startedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationCode,
    this.completedAt,
  }) : amountDue = amountDue ?? estimatedFare,
       grossFare = grossFare ?? amountDue ?? estimatedFare,
       driverNetEarnings =
           driverNetEarnings ?? grossFare ?? amountDue ?? estimatedFare;

  //==========================================================================
  // Identity
  //==========================================================================

  final int schemaVersion;

  final String bookingId;

  final String passengerId;
  final String? passengerName;
  final String? passengerPhone;
  final String? passengerPhotoUrl;

  final String? driverId;

  //==========================================================================
  // Driver Snapshot
  //==========================================================================

  /// Copied when a driver accepts the booking.
  /// This allows passenger screens to display driver
  /// information without extra Firestore queries.

  final String? driverName;

  final String? driverPhotoUrl;

  final double? driverRating;

  final String? vehicleNumber;

  final String? plateNumber;

  final String? todaId;

  final String? todaName;

  //==========================================================================
  // Trip
  //==========================================================================

  final LatLng pickup;

  final LatLng destination;

  final String pickupAddress;

  final String destinationAddress;

  final int distanceMeters;

  final double estimatedFare;
  final String authoritativeRoutePolyline;
  final int fareVersion;
  final Map<String, dynamic> fareSnapshot;
  final Map<String, dynamic> fareBreakdown;
  final DateTime? searchExpiresAt;
  final String paymentMethod;
  final double amountDue;
  final double grossFare;
  final double commissionPercent;
  final double commissionAmount;
  final double driverNetEarnings;
  final DateTime? passengerPaidAt;
  final DateTime? driverReceivedAt;
  final String settlementStatus;
  final String? receiptNumber;

  final int additionalPassengers;

  final int baggageCount;

  final bool isOutsideToda;

  final int routePolicyVersion;

  final RoutePolicyAdvisory routePolicy;

  //==========================================================================
  // Status
  //==========================================================================

  final BookingStatus status;

  //==========================================================================
  // Dates
  //==========================================================================

  final DateTime createdAt;

  final DateTime updatedAt;

  final DateTime? assignedAt;

  final DateTime? arrivedAt;

  final DateTime? pickupConfirmedAt;

  final DateTime? startedAt;

  final DateTime? cancelledAt;

  final String? cancelledBy;

  final String? cancellationCode;

  /// Nullable because old bookings won't have this field.
  final DateTime? completedAt;

  //==========================================================================
  // Firestore
  //==========================================================================

  factory Booking.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Booking.fromMap(
      bookingId: doc.id,
      data: doc.data() ?? const <String, dynamic>{},
    );
  }

  /// Parses both current bookings and legacy/partially migrated documents.
  ///
  /// Firestore is schemaless, so user-facing history and recovery must not
  /// crash merely because an older optional snapshot field is absent.
  factory Booking.fromMap({
    required String bookingId,
    required Map<String, dynamic> data,
  }) {
    final pickup = _parseLatLng(
      data['pickup'],
      latitude: data['pickupLatitude'],
      longitude: data['pickupLongitude'],
    );
    final destination = _parseLatLng(
      data['destination'],
      latitude: data['destinationLatitude'],
      longitude: data['destinationLongitude'],
    );

    return Booking(
      schemaVersion: _asInt(data['schemaVersion'], fallback: 0),
      bookingId: bookingId,
      passengerId: _asString(data['passengerId']),
      passengerName: _asNullableString(data['passengerName']),
      passengerPhone: _asNullableString(data['passengerPhone']),
      passengerPhotoUrl: _asNullableString(data['passengerPhotoUrl']),
      driverId: _asNullableString(data['driverId']),

      //=========================
      // Driver Snapshot
      //=========================
      driverName: _asNullableString(data['driverName']),
      driverPhotoUrl: _asNullableString(data['driverPhotoUrl']),
      driverRating: _asNullableDouble(data['driverRating']),
      vehicleNumber: _asNullableString(data['vehicleNumber']),
      plateNumber: _asNullableString(data['plateNumber']),
      todaId: _asNullableString(data['todaId']),
      todaName: _asNullableString(data['todaName']),

      pickup: pickup,
      destination: destination,
      pickupAddress: _firstReadable([
        data['pickupAddress'],
        data['pickupName'],
      ], fallback: 'Pickup location'),
      destinationAddress: _firstReadable([
        data['destinationAddress'],
        data['destinationName'],
        data['dropoffAddress'],
      ], fallback: 'Destination'),
      distanceMeters: _asInt(data['distanceMeters']),
      estimatedFare: _asDouble(data['estimatedFare']),
      authoritativeRoutePolyline: _asString(data['authoritativeRoutePolyline']),
      fareVersion: _asInt(
        data['fareVersion'],
        fallback: _asInt(_stringKeyedMap(data['fareSnapshot'])['version']),
      ),
      fareSnapshot: _stringKeyedMap(data['fareSnapshot']),
      fareBreakdown: _stringKeyedMap(data['fareBreakdown']),
      searchExpiresAt: parseModelDate(data['searchExpiresAt']),
      paymentMethod: _asString(data['paymentMethod'], fallback: 'cash'),
      amountDue: _asDouble(
        data['amountDue'],
        fallback: _asDouble(data['estimatedFare']),
      ),
      grossFare: _asDouble(
        data['grossFare'],
        fallback: _asDouble(
          data['amountDue'],
          fallback: _asDouble(data['estimatedFare']),
        ),
      ),
      commissionPercent: _asDouble(data['commissionPercent']),
      commissionAmount: _asDouble(data['commissionAmount']),
      driverNetEarnings: _asDouble(
        data['driverNetEarnings'],
        fallback: _asDouble(
          data['grossFare'],
          fallback: _asDouble(
            data['amountDue'],
            fallback: _asDouble(data['estimatedFare']),
          ),
        ),
      ),
      passengerPaidAt: parseModelDate(data['passengerPaidAt']),
      driverReceivedAt: parseModelDate(data['driverReceivedAt']),
      settlementStatus: _asString(
        data['settlementStatus'],
        fallback: 'awaiting_confirmation',
      ),
      receiptNumber: _asNullableString(data['receiptNumber']),
      additionalPassengers: _asInt(data['additionalPassengers']),
      baggageCount: _asInt(data['baggageCount']),
      isOutsideToda: data['isOutsideToda'] == true,
      routePolicyVersion: _asInt(data['routePolicyVersion']),
      routePolicy:
          RoutePolicyAdvisory.fromMap(
            data['highwayRouteAdvisory'] ?? data['routeAdvisory'],
          ).copyWith(
            avoidedRestrictionNames: _stringList(
              data['avoidedRouteRestrictionNames'],
            ),
          ),
      status: _parseStatus(data['status']),
      createdAt: parseModelDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: parseModelDate(data['updatedAt']) ?? DateTime.now(),
      assignedAt: parseModelDate(data['assignedAt']),
      arrivedAt: parseModelDate(data['arrivedAt']),
      pickupConfirmedAt: parseModelDate(data['pickupConfirmedAt']),
      startedAt: parseModelDate(data['startedAt']),
      cancelledAt: parseModelDate(data['cancelledAt']),
      cancelledBy: _asNullableString(data['cancelledBy']),
      cancellationCode: _asNullableString(data['cancellationCode']),
      completedAt: parseModelDate(data['completedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schemaVersion': currentSchemaVersion,

      //======================================================================
      // Identity
      //======================================================================
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerPhotoUrl': passengerPhotoUrl,
      'driverId': driverId,

      //======================================================================
      // Driver Snapshot
      //======================================================================
      'driverName': driverName,
      'driverPhotoUrl': driverPhotoUrl,
      'driverRating': driverRating,
      'vehicleNumber': vehicleNumber,
      'plateNumber': plateNumber,
      'todaId': todaId,
      'todaName': todaName,

      //======================================================================
      // Trip
      //======================================================================
      'pickup': {'latitude': pickup.latitude, 'longitude': pickup.longitude},
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'distanceMeters': distanceMeters,
      'estimatedFare': estimatedFare,
      'authoritativeRoutePolyline': authoritativeRoutePolyline,
      'fareVersion': fareVersion,
      'fareSnapshot': fareSnapshot,
      'fareBreakdown': fareBreakdown,
      'searchExpiresAt': searchExpiresAt == null
          ? null
          : Timestamp.fromDate(searchExpiresAt!),
      'paymentMethod': paymentMethod,
      'amountDue': amountDue,
      'grossFare': grossFare,
      'commissionPercent': commissionPercent,
      'commissionAmount': commissionAmount,
      'driverNetEarnings': driverNetEarnings,
      'passengerPaidAt': passengerPaidAt == null
          ? null
          : Timestamp.fromDate(passengerPaidAt!),
      'driverReceivedAt': driverReceivedAt == null
          ? null
          : Timestamp.fromDate(driverReceivedAt!),
      'settlementStatus': settlementStatus,
      'receiptNumber': receiptNumber,
      'additionalPassengers': additionalPassengers,
      'baggageCount': baggageCount,
      'isOutsideToda': isOutsideToda,
      'routePolicyVersion': routePolicyVersion,
      'highwayRouteAdvisory': routePolicy.toMap(),

      //======================================================================
      // Status
      //======================================================================
      'status': status.name,

      //======================================================================
      // Dates
      //======================================================================
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'assignedAt': assignedAt == null ? null : Timestamp.fromDate(assignedAt!),
      'arrivedAt': arrivedAt == null ? null : Timestamp.fromDate(arrivedAt!),
      'pickupConfirmedAt': pickupConfirmedAt == null
          ? null
          : Timestamp.fromDate(pickupConfirmedAt!),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'cancelledAt': cancelledAt == null
          ? null
          : Timestamp.fromDate(cancelledAt!),
      'cancelledBy': cancelledBy,
      'cancellationCode': cancellationCode,
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
    };
  }

  //==========================================================================
  // Copy
  //==========================================================================

  Booking copyWith({
    int? schemaVersion,
    String? bookingId,
    String? passengerId,
    String? passengerName,
    String? passengerPhone,
    String? passengerPhotoUrl,
    String? driverId,

    //======================================================================
    // Driver Snapshot
    //======================================================================
    String? driverName,
    String? driverPhotoUrl,
    double? driverRating,
    String? vehicleNumber,
    String? plateNumber,
    String? todaId,
    String? todaName,

    //======================================================================
    // Trip
    //======================================================================
    LatLng? pickup,
    LatLng? destination,
    String? pickupAddress,
    String? destinationAddress,
    int? distanceMeters,
    double? estimatedFare,
    String? authoritativeRoutePolyline,
    int? fareVersion,
    Map<String, dynamic>? fareSnapshot,
    Map<String, dynamic>? fareBreakdown,
    DateTime? searchExpiresAt,
    String? paymentMethod,
    double? amountDue,
    double? grossFare,
    double? commissionPercent,
    double? commissionAmount,
    double? driverNetEarnings,
    DateTime? passengerPaidAt,
    DateTime? driverReceivedAt,
    String? settlementStatus,
    String? receiptNumber,
    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,
    int? routePolicyVersion,
    RoutePolicyAdvisory? routePolicy,

    //======================================================================
    // Status
    //======================================================================
    BookingStatus? status,

    //======================================================================
    // Dates
    //======================================================================
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? assignedAt,
    DateTime? arrivedAt,
    DateTime? pickupConfirmedAt,
    DateTime? startedAt,
    DateTime? cancelledAt,
    String? cancelledBy,
    String? cancellationCode,
    DateTime? completedAt,
  }) {
    return Booking(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      bookingId: bookingId ?? this.bookingId,
      passengerId: passengerId ?? this.passengerId,
      passengerName: passengerName ?? this.passengerName,
      passengerPhone: passengerPhone ?? this.passengerPhone,
      passengerPhotoUrl: passengerPhotoUrl ?? this.passengerPhotoUrl,
      driverId: driverId ?? this.driverId,

      //====================================================================
      // Driver Snapshot
      //====================================================================
      driverName: driverName ?? this.driverName,
      driverPhotoUrl: driverPhotoUrl ?? this.driverPhotoUrl,
      driverRating: driverRating ?? this.driverRating,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      plateNumber: plateNumber ?? this.plateNumber,
      todaId: todaId ?? this.todaId,
      todaName: todaName ?? this.todaName,

      //====================================================================
      // Trip
      //====================================================================
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      estimatedFare: estimatedFare ?? this.estimatedFare,
      authoritativeRoutePolyline:
          authoritativeRoutePolyline ?? this.authoritativeRoutePolyline,
      fareVersion: fareVersion ?? this.fareVersion,
      fareSnapshot: fareSnapshot ?? this.fareSnapshot,
      fareBreakdown: fareBreakdown ?? this.fareBreakdown,
      searchExpiresAt: searchExpiresAt ?? this.searchExpiresAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amountDue: amountDue ?? this.amountDue,
      grossFare: grossFare ?? this.grossFare,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      driverNetEarnings: driverNetEarnings ?? this.driverNetEarnings,
      passengerPaidAt: passengerPaidAt ?? this.passengerPaidAt,
      driverReceivedAt: driverReceivedAt ?? this.driverReceivedAt,
      settlementStatus: settlementStatus ?? this.settlementStatus,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      additionalPassengers: additionalPassengers ?? this.additionalPassengers,
      baggageCount: baggageCount ?? this.baggageCount,
      isOutsideToda: isOutsideToda ?? this.isOutsideToda,
      routePolicyVersion: routePolicyVersion ?? this.routePolicyVersion,
      routePolicy: routePolicy ?? this.routePolicy,

      //====================================================================
      // Status
      //====================================================================
      status: status ?? this.status,

      //====================================================================
      // Dates
      //====================================================================
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedAt: assignedAt ?? this.assignedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      pickupConfirmedAt: pickupConfirmedAt ?? this.pickupConfirmedAt,
      startedAt: startedAt ?? this.startedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancellationCode: cancellationCode ?? this.cancellationCode,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

String _asString(Object? value, {String fallback = ''}) {
  return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
}

String? _asNullableString(Object? value) {
  final parsed = _asString(value);
  return parsed.isEmpty ? null : parsed;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num && value.isFinite) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? _asNullableDouble(Object? value) {
  if (value == null) return null;
  return _asDouble(value);
}

String _firstReadable(List<Object?> values, {required String fallback}) {
  for (final value in values) {
    final text = _asString(value);
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

BookingStatus _parseStatus(Object? value) {
  final name = _asString(value);
  for (final status in BookingStatus.values) {
    if (status.name == name) return status;
  }
  throw FormatException(
    'Unsupported booking status: ${name.isEmpty ? '<empty>' : name}',
  );
}

Map<String, dynamic> _stringKeyedMap(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  return Map<String, dynamic>.unmodifiable({
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  });
}

LatLng _parseLatLng(Object? value, {Object? latitude, Object? longitude}) {
  if (value is GeoPoint) {
    return LatLng(value.latitude, value.longitude);
  }
  if (value is Map) {
    final map = Map<Object?, Object?>.from(value);
    return LatLng(
      _asDouble(map['latitude'] ?? map['lat']),
      _asDouble(map['longitude'] ?? map['lng']),
    );
  }
  return LatLng(_asDouble(latitude), _asDouble(longitude));
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
