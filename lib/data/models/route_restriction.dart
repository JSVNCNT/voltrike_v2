import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteRestriction {
  const RouteRestriction({
    required this.id,
    required this.name,
    required this.type,
    required this.polygon,
    required this.isActive,
    this.geometryType = 'polygon',
    this.bufferMeters = 0,
    this.areas = const [],
    this.notes = '',
  });

  final String id;
  final String name;
  final String type;
  final List<LatLng> polygon;
  final String geometryType;
  final int bufferMeters;
  final List<List<LatLng>> areas;
  final bool isActive;
  final String notes;

  factory RouteRestriction.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawPolygon = data['coordinates'] as List? ?? data['polygon'] as List? ?? const [];
    final parsedPolygon = rawPolygon.whereType<List>().where((point) => point.length == 2).map((point) => LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble())).toList();
    final rawAreas = data['areas'] as List?;
    final parsedAreas = rawAreas == null ? <List<LatLng>>[parsedPolygon] : rawAreas.whereType<List>().map((area) => area.whereType<List>().where((point) => point.length == 2).map((point) => LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble())).toList()).where((area) => area.isNotEmpty).toList();
    return RouteRestriction(
      id: document.id,
      name: data['name'] as String? ?? 'Restricted area',
      type: data['type'] as String? ?? 'no_service_area',
      polygon: parsedPolygon,
      areas: parsedAreas,
      geometryType: data['geometryType'] as String? ?? 'polygon',
      bufferMeters: (data['bufferMeters'] as num?)?.round() ?? 0,
      isActive: data['isActive'] as bool? ?? false,
      notes: data['notes'] as String? ?? '',
    );
  }
}
