import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/models/route_restriction.dart';

/// Caches developer-controlled road and area restrictions for route selection.
class RouteRestrictionService {
  RouteRestrictionService._();

  static final RouteRestrictionService instance = RouteRestrictionService._();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<RouteRestriction>? _cache;
  DateTime? _loadedAt;
  RouteRestriction? _lastConflict;

  RouteRestriction? get lastConflict => _lastConflict;

  Future<List<RouteRestriction>> activeRestrictions() async {
    if (_cache != null && _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
      return _cache!;
    }
    final snapshot = await _firestore
        .collection('routeRestrictions')
        .where('isActive', isEqualTo: true)
        .get();
    _cache = snapshot.docs.map(RouteRestriction.fromFirestore).toList();
    _loadedAt = DateTime.now();
    return _cache!;
  }

  void invalidate() { _cache = null; _loadedAt = null; }

  void markConflict(RouteRestriction restriction) {
    _lastConflict = restriction;
  }

  void clearLastConflict() => _lastConflict = null;

  Future<RouteRestriction?> routeConflict(List<LatLng> route) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (restriction.polygon.length >= 3 &&
          _routeIntersects(route, restriction.polygon)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  Future<RouteRestriction?> pointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (restriction.polygon.length >= 3 && _contains(point, restriction.polygon)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  bool _contains(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects = ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude < (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) + a.longitude);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _routeIntersects(List<LatLng> route, List<LatLng> polygon) {
    if (route.any((point) => _contains(point, polygon))) return true;
    for (var i = 1; i < route.length; i++) {
      for (var j = 0; j < polygon.length; j++) {
        if (_segmentsIntersect(
          route[i - 1],
          route[i],
          polygon[j],
          polygon[(j + 1) % polygon.length],
        )) return true;
      }
    }
    return false;
  }

  bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
    double cross(LatLng p, LatLng q, LatLng r) =>
        (q.longitude - p.longitude) * (r.latitude - p.latitude) -
        (q.latitude - p.latitude) * (r.longitude - p.longitude);
    final abC = cross(a, b, c);
    final abD = cross(a, b, d);
    final cdA = cross(c, d, a);
    final cdB = cross(c, d, b);
    return ((abC > 0 && abD < 0) || (abC < 0 && abD > 0)) &&
        ((cdA > 0 && cdB < 0) || (cdA < 0 && cdB > 0));
  }
}
