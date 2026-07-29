import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../data/models/route_restriction.dart';

/// Pure, deterministic restriction geometry shared by runtime code and tests.
class RouteRestrictionMatcher {
  const RouteRestrictionMatcher._();

  static bool isEnforcedPolygon(RouteRestriction restriction) {
    if (!restriction.isActive || restriction.geometryType == 'corridor') {
      return false;
    }
    return restriction.type == 'no_service_area' ||
        restriction.type == 'restricted_crossing' ||
        restriction.type == 'restricted_driving_area';
  }

  static bool routeConflicts(List<LatLng> route, RouteRestriction restriction) {
    if (!isEnforcedPolygon(restriction) || route.length < 2) return false;
    return restriction.areas.any(
      (area) => area.length >= 3 && _routeIntersects(route, area),
    );
  }

  static bool pointConflicts(LatLng point, RouteRestriction restriction) {
    if (!isEnforcedPolygon(restriction)) return false;
    return restriction.areas.any(
      (area) => area.length >= 3 && _contains(point, area),
    );
  }

  /// Distance to the closest polygon edge. A point inside returns zero.
  ///
  /// Legacy highway corridors are deliberately excluded from this API. They
  /// cannot distinguish legal perpendicular crossings from highway travel and
  /// therefore must never create a live driver violation.
  static double distanceToEnforcedPolygonMeters(
    LatLng point,
    RouteRestriction restriction,
  ) {
    if (!isEnforcedPolygon(restriction)) return double.infinity;
    var closest = double.infinity;
    for (final area in restriction.areas) {
      if (area.length < 3) continue;
      if (_contains(point, area)) return 0;
      for (var index = 0; index < area.length; index++) {
        closest = math.min(
          closest,
          _pointToSegmentMeters(
            point,
            area[index],
            area[(index + 1) % area.length],
          ),
        );
      }
    }
    return closest;
  }

  static bool _contains(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      if (_pointOnSegment(point, a, b)) return true;
      final intersects =
          ((a.latitude > point.latitude) != (b.latitude > point.latitude)) &&
          (point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  static bool _routeIntersects(List<LatLng> route, List<LatLng> polygon) {
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

  static double _pointToSegmentMeters(LatLng point, LatLng start, LatLng end) {
    const metresPerDegree = 111320.0;
    final referenceLatitude =
        (point.latitude + start.latitude + end.latitude) / 3 * math.pi / 180;
    final scaleLongitude = metresPerDegree * math.cos(referenceLatitude);
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

  static bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    if (abC != abD && cdA != cdB) return true;
    return (abC == 0 && _pointOnSegment(c, a, b)) ||
        (abD == 0 && _pointOnSegment(d, a, b)) ||
        (cdA == 0 && _pointOnSegment(a, c, d)) ||
        (cdB == 0 && _pointOnSegment(b, c, d));
  }

  static int _orientation(LatLng a, LatLng b, LatLng c) {
    final value =
        (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
    if (value.abs() <= 1e-12) return 0;
    return value > 0 ? 1 : -1;
  }

  static bool _pointOnSegment(LatLng point, LatLng start, LatLng end) {
    const epsilon = 1e-10;
    final cross =
        (point.latitude - start.latitude) * (end.longitude - start.longitude) -
        (point.longitude - start.longitude) * (end.latitude - start.latitude);
    if (cross.abs() > epsilon) return false;
    return point.latitude >= math.min(start.latitude, end.latitude) - epsilon &&
        point.latitude <= math.max(start.latitude, end.latitude) + epsilon &&
        point.longitude >= math.min(start.longitude, end.longitude) - epsilon &&
        point.longitude <= math.max(start.longitude, end.longitude) + epsilon;
  }
}

/// Caches developer-controlled road and area restrictions for route selection.
class RouteRestrictionService {
  RouteRestrictionService._();

  static final RouteRestrictionService instance = RouteRestrictionService._();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<RouteRestriction>? _cache;
  DateTime? _loadedAt;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  RouteRestriction? _lastConflict;

  RouteRestriction? get lastConflict => _lastConflict;

  Future<List<RouteRestriction>> activeRestrictions() async {
    _ensureLiveUpdates();
    if (_cache != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return _cache!;
    }
    final snapshot = await _activeQuery.get();
    _replaceCache(snapshot);
    return _cache!;
  }

  Query<Map<String, dynamic>> get _activeQuery => _firestore
      .collection('routeRestrictions')
      .where('isActive', isEqualTo: true);

  void _ensureLiveUpdates() {
    _subscription ??= _activeQuery.snapshots().listen(
      _replaceCache,
      onError: (_) {
        // The bounded fetch above remains the fallback while Firestore
        // reconnects or the current account is not allowed to subscribe.
        _subscription = null;
      },
      onDone: () => _subscription = null,
      cancelOnError: true,
    );
  }

  void _replaceCache(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _cache = snapshot.docs.map(RouteRestriction.fromFirestore).toList();
    _loadedAt = DateTime.now();
  }

  void invalidate() {
    _cache = null;
    _loadedAt = null;
  }

  void markConflict(RouteRestriction restriction) {
    _lastConflict = restriction;
  }

  void clearLastConflict() => _lastConflict = null;

  Future<RouteRestriction?> routeConflict(List<LatLng> route) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (RouteRestrictionMatcher.routeConflicts(route, restriction)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  Future<RouteRestriction?> pointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (RouteRestrictionMatcher.pointConflicts(point, restriction)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }

  Future<RouteRestriction?> bookingEndpointConflict(LatLng point) async {
    final restrictions = await activeRestrictions();
    for (final restriction in restrictions) {
      if (RouteRestrictionMatcher.isEnforcedPolygon(restriction) &&
          RouteRestrictionMatcher.pointConflicts(point, restriction)) {
        _lastConflict = restriction;
        return restriction;
      }
    }
    return null;
  }
}
