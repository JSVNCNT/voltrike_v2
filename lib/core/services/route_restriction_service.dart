import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

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
      final conflicts = restriction.geometryType == 'corridor'
          ? restriction.polygon.length >= 2 &&
              route.any((point) => _nearCorridor(
                    point,
                    restriction.polygon,
                    restriction.bufferMeters,
                  ))
          : restriction.areas.any((area) =>
              area.length >= 3 && _routeIntersects(route, area));
      if (conflicts) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  Future<RouteRestriction?> pointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      final conflicts = restriction.geometryType == 'corridor'
          ? restriction.polygon.length >= 2 &&
              _nearCorridor(
                point,
                restriction.polygon,
                restriction.bufferMeters,
              )
          : restriction.areas.any((area) =>
              area.length >= 3 && _contains(point, area));
      if (conflicts) {
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
        )) {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks a buffered road centreline in metres. This avoids pretending a
  /// highway is an area while still catching GPS samples near curved roads.
  bool _nearCorridor(
    LatLng point,
    List<LatLng> centreline,
    int bufferMeters,
  ) {
    for (var index = 1; index < centreline.length; index++) {
      if (_pointToSegmentMeters(
            point,
            centreline[index - 1],
            centreline[index],
          ) <=
          bufferMeters) {
        return true;
      }
    }
    return false;
  }

  double _pointToSegmentMeters(LatLng point, LatLng start, LatLng end) {
    const metresPerDegree = 111320.0;
    final referenceLatitude =
        (point.latitude + start.latitude + end.latitude) / 3 * 3.141592653589793 / 180;
    final scaleLongitude = metresPerDegree *
        // Equirectangular projection is accurate enough for short road spans.
        math.cos(referenceLatitude);
    final px = (point.longitude - start.longitude) * scaleLongitude;
    final py = (point.latitude - start.latitude) * metresPerDegree;
    final sx = (end.longitude - start.longitude) * scaleLongitude;
    final sy = (end.latitude - start.latitude) * metresPerDegree;
    final lengthSquared = sx * sx + sy * sy;
    if (lengthSquared == 0) return math.sqrt(px * px + py * py);
    final projection = ((px * sx + py * sy) / lengthSquared).clamp(0.0, 1.0);
    final dx = px - sx * projection;
    final dy = py - sy * projection;
    return math.sqrt(dx * dx + dy * dy);
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
