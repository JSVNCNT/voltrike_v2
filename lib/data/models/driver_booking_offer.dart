import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_policy_advisory.dart';

class DriverBookingOffer {
  const DriverBookingOffer({
    required this.bookingId,
    required this.expiresAt,
    this.distanceMeters = 0,
    this.servicePriority = 0,
    this.queueEnteredAt,
    this.bookingCreatedAt,
    this.createdAt,
    this.stableId = '',
    this.routePolicy = const RoutePolicyAdvisory(),
  });

  final String bookingId;
  final DateTime expiresAt;
  final int distanceMeters;
  final int servicePriority;
  final DateTime? queueEnteredAt;
  final DateTime? bookingCreatedAt;
  final DateTime? createdAt;
  final String stableId;
  final RoutePolicyAdvisory routePolicy;

  DateTime get effectiveQueueTime =>
      queueEnteredAt ?? bookingCreatedAt ?? createdAt ?? expiresAt;

  factory DriverBookingOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return DriverBookingOffer.fromMap(
      documentId: document.id,
      data: document.data() ?? const <String, dynamic>{},
    );
  }

  factory DriverBookingOffer.fromMap({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    final bookingId = _string(data['bookingId']) ?? documentId;
    return DriverBookingOffer(
      bookingId: bookingId,
      expiresAt:
          _date(data['expiresAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      distanceMeters: (data['distanceMeters'] as num?)?.round() ?? 0,
      servicePriority: (data['servicePriority'] as num?)?.round() ?? 0,
      queueEnteredAt: _date(data['queueEnteredAt']),
      bookingCreatedAt: _date(data['bookingCreatedAt']),
      createdAt: _date(data['createdAt']),
      stableId: _string(data['offerId']) ?? bookingId,
      routePolicy:
          RoutePolicyAdvisory.fromMap(
            data['highwayRouteAdvisory'] ?? data['routeAdvisory'],
          ).copyWith(
            avoidedRestrictionNames: _strings(
              data['avoidedRouteRestrictionNames'],
            ),
          ),
    );
  }

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  /// Oldest passenger queue entry wins UI position, followed by the
  /// server-owned service tier, pickup distance, and a stable server ID.
  static int compareForDisplay(
    DriverBookingOffer left,
    DriverBookingOffer right,
  ) {
    final queueOrder = left.effectiveQueueTime.compareTo(
      right.effectiveQueueTime,
    );
    if (queueOrder != 0) return queueOrder;
    final priorityOrder = left.servicePriority.compareTo(right.servicePriority);
    if (priorityOrder != 0) return priorityOrder;
    final distanceOrder = left.distanceMeters.compareTo(right.distanceMeters);
    if (distanceOrder != 0) return distanceOrder;
    return left.stableId.compareTo(right.stableId);
  }
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

List<String> _strings(Object? value) {
  if (value is! Iterable) return const [];
  return value.whereType<String>().toSet().toList(growable: false);
}
