import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import 'model_date_parser.dart';

class DriverViolationCase {
  const DriverViolationCase({
    required this.id,
    required this.driverId,
    required this.restrictionId,
    required this.restrictionName,
    required this.restrictionType,
    required this.status,
    required this.eventClass,
    required this.eventLocation,
    required this.createdAt,
    this.schemaVersion = 1,
    this.ownerTodaId,
    this.bookingId,
    this.context = 'online_idle',
    this.accuracyMeters,
    this.source = 'device_polygon_monitor',
    this.confidence = 'confirmed_two_sample',
    this.lastDetectedAt,
    this.resolvedAt,
  });

  final String id;
  final int schemaVersion;
  final String driverId;
  final String? ownerTodaId;
  final String? bookingId;
  final String restrictionId;
  final String restrictionName;
  final String restrictionType;
  final String status;
  final String eventClass;
  final String context;
  final LatLng eventLocation;
  final double? accuracyMeters;
  final String source;
  final String confidence;
  final DateTime createdAt;
  final DateTime? lastDetectedAt;
  final DateTime? resolvedAt;

  bool get isOpen =>
      status == 'open' || status == 'acknowledged' || status == 'responding';

  factory DriverViolationCase.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return DriverViolationCase.fromMap(
      id: document.id,
      data: document.data() ?? const {},
    );
  }

  factory DriverViolationCase.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final restriction = _map(data['restriction']);
    final location = _latLng(
      data['eventLocation'] ?? data['location'] ?? data['entryLocation'],
    );
    return DriverViolationCase(
      id: id,
      schemaVersion: _integer(data['schemaVersion']) ?? 1,
      driverId: _text(data['driverId']) ?? '',
      ownerTodaId:
          _text(data['ownerTodaId']) ??
          _text(data['todaId']) ??
          _text(data['driverTodaId']),
      bookingId: _text(data['bookingId']),
      restrictionId:
          _text(restriction['id']) ?? _text(data['restrictionId']) ?? '',
      restrictionName:
          _text(restriction['name']) ??
          _text(data['restrictionName']) ??
          'Restricted area',
      restrictionType:
          _text(restriction['type']) ??
          _text(data['restrictionType']) ??
          'no_service_area',
      status: _text(data['status']) ?? 'open',
      eventClass: _text(data['eventClass']) ?? 'restricted_area_entry',
      context: _text(data['context']) ?? 'online_idle',
      eventLocation: location ?? const LatLng(0, 0),
      accuracyMeters: _number(
        _map(data['eventLocation'])['accuracyMeters'] ??
            _map(data['eventLocation'])['accuracy'] ??
            data['accuracyMeters'],
      ),
      source: _text(data['source']) ?? 'server_verified',
      confidence: _text(data['confidence']) ?? 'server_verified',
      createdAt:
          parseModelDate(data['occurredAt']) ??
          parseModelDate(data['createdAt']) ??
          DateTime.now(),
      lastDetectedAt:
          parseModelDate(data['lastDetectedAt']) ??
          parseModelDate(data['updatedAt']),
      resolvedAt: parseModelDate(data['resolvedAt']),
    );
  }
}

class DriverViolationMessage {
  const DriverViolationMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
    this.senderName,
  });

  final String id;
  final String senderId;
  final String senderRole;
  final String? senderName;
  final String text;
  final DateTime createdAt;

  factory DriverViolationMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return DriverViolationMessage(
      id: document.id,
      senderId: _text(data['senderId']) ?? '',
      senderRole: _text(data['senderRole']) ?? 'admin',
      senderName: _text(data['senderName']),
      text: _text(data['body'] ?? data['text']) ?? '',
      createdAt:
          parseModelDate(data['sentAt']) ??
          parseModelDate(data['createdAt']) ??
          DateTime.now(),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

int? _integer(Object? value) {
  if (value is num && value.isFinite) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

double? _number(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

LatLng? _latLng(Object? value) {
  if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
  final map = _map(value);
  final latitude = _number(map['latitude'] ?? map['lat']);
  final longitude = _number(map['longitude'] ?? map['lng']);
  if (latitude == null || longitude == null) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return null;
  }
  return LatLng(latitude, longitude);
}
