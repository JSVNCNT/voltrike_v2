import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

class RouteRestriction {
  const RouteRestriction({
    required this.id,
    required this.name,
    required this.type,
    required this.polygon,
    required this.isActive,
    this.geometryVersion = 1,
    this.geometryType = 'polygon',
    this.bufferMeters = 0,
    this.minimumAlignedTravelMeters = 80,
    this.areas = const [],
    this.notes = '',
  });

  final String id;
  final String name;
  final String type;
  final List<LatLng> polygon;
  final int geometryVersion;
  final String geometryType;
  final int bufferMeters;

  /// Highway corridors only: route travel parallel to the centreline must
  /// exceed this distance before it is treated as prohibited highway travel.
  final int minimumAlignedTravelMeters;
  final List<List<LatLng>> areas;
  final bool isActive;
  final String notes;

  factory RouteRestriction.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return RouteRestriction.fromMap(
      id: document.id,
      data: document.data() ?? const <String, dynamic>{},
    );
  }

  factory RouteRestriction.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final parsedAreas = _parseAreas(data['areas']);
    var parsedPolygon = _parseArea(data['coordinates']);
    if (parsedPolygon.isEmpty) {
      parsedPolygon = _parseArea(data['polygon']);
    }
    if (parsedPolygon.isEmpty && parsedAreas.isNotEmpty) {
      parsedPolygon = parsedAreas.first;
    }

    final effectiveAreas = parsedAreas.isNotEmpty
        ? parsedAreas
        : parsedPolygon.isEmpty
        ? const <List<LatLng>>[]
        : <List<LatLng>>[parsedPolygon];

    return RouteRestriction(
      id: id,
      name: data['name'] as String? ?? 'Restricted area',
      type: data['type'] as String? ?? 'no_service_area',
      polygon: parsedPolygon,
      geometryVersion: (data['geometryVersion'] as num?)?.round() ?? 1,
      areas: effectiveAreas,
      geometryType: data['geometryType'] as String? ?? 'polygon',
      bufferMeters: (data['bufferMeters'] as num?)?.round() ?? 0,
      minimumAlignedTravelMeters:
          (data['minimumAlignedTravelMeters'] as num?)?.round() ?? 80,
      isActive: data['isActive'] as bool? ?? false,
      notes: data['notes'] as String? ?? '',
    );
  }
}

List<List<LatLng>> _parseAreas(Object? value) {
  if (value is Map) {
    final wrappedArea = _parseArea(value);
    return wrappedArea.isEmpty ? const <List<LatLng>>[] : [wrappedArea];
  }
  if (value is! Iterable) return const <List<LatLng>>[];

  final entries = value.toList(growable: false);
  if (entries.isEmpty) return const <List<LatLng>>[];

  if (_parsePoint(entries.first) != null) {
    final area = _parseArea(entries);
    return area.isEmpty ? const <List<LatLng>>[] : [area];
  }

  return entries
      .map(_parseArea)
      .where((area) => area.isNotEmpty)
      .toList(growable: false);
}

List<LatLng> _parseArea(Object? value) {
  Object? points = value;
  if (value is Map) {
    points =
        value['points'] ??
        value['coordinates'] ??
        value['vertices'] ??
        value['polygon'];
  }
  if (points is! Iterable) return const <LatLng>[];

  return points.map(_parsePoint).whereType<LatLng>().toList(growable: false);
}

LatLng? _parsePoint(Object? value) {
  if (value is LatLng) return value;
  if (value is GeoPoint) {
    return _validatedLatLng(value.latitude, value.longitude);
  }
  if (value is Map) {
    final latitude = value['latitude'] ?? value['lat'];
    final longitude = value['longitude'] ?? value['lng'] ?? value['lon'];
    if (latitude is num && longitude is num) {
      return _validatedLatLng(latitude.toDouble(), longitude.toDouble());
    }
    return null;
  }
  if (value is List &&
      value.length >= 2 &&
      value[0] is num &&
      value[1] is num) {
    return _validatedLatLng(
      (value[1] as num).toDouble(),
      (value[0] as num).toDouble(),
    );
  }
  return null;
}

LatLng? _validatedLatLng(double latitude, double longitude) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    return null;
  }
  return LatLng(latitude, longitude);
}
