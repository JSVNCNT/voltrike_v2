import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteRestriction {
  const RouteRestriction({
    required this.id,
    required this.name,
    required this.type,
    required this.polygon,
    required this.isActive,
    this.notes = '',
  });

  final String id;
  final String name;
  final String type;
  final List<LatLng> polygon;
  final bool isActive;
  final String notes;

  factory RouteRestriction.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawPolygon = data['polygon'] as List? ?? const [];
    return RouteRestriction(
      id: document.id,
      name: data['name'] as String? ?? 'Restricted area',
      type: data['type'] as String? ?? 'no_service_area',
      polygon: rawPolygon.whereType<List>().where((point) => point.length == 2).map((point) => LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble())).toList(),
      isActive: data['isActive'] as bool? ?? false,
      notes: data['notes'] as String? ?? '',
    );
  }
}
