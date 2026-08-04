import 'dart:math' as math;

import '../../data/models/route_restriction.dart';
import '../maps/voltrike_map.dart';

class RouteRestrictionProximity {
  const RouteRestrictionProximity({
    this.insideRestrictionIndex,
    this.nearestRestrictionIndex,
    this.nearestDistanceMeters,
    this.preferredDistanceMeters,
  });

  final int? insideRestrictionIndex;
  final int? nearestRestrictionIndex;
  final double? nearestDistanceMeters;
  final double? preferredDistanceMeters;
}

class HighwayTravelMatch {
  const HighwayTravelMatch({
    required this.restriction,
    required this.alignedTravelMeters,
  });

  final RouteRestriction restriction;
  final double alignedTravelMeters;
}

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

  static bool isHighwayCorridor(RouteRestriction restriction) =>
      restriction.isActive &&
      restriction.type == 'prohibited_highway' &&
      restriction.geometryType == 'corridor' &&
      restriction.bufferMeters > 0;

  /// Finds highway *travel*, not a simple crossing. The route is sampled at
  /// short intervals, and only movement roughly parallel to the centreline is
  /// accumulated. This lets ordinary cross streets remain legal.
  static HighwayTravelMatch? firstHighwayTravelConflict(
    List<LatLng> route,
    List<RouteRestriction> restrictions,
  ) {
    if (route.length < 2) return null;
    for (final restriction in restrictions) {
      if (!isHighwayCorridor(restriction)) continue;
      final alignedMeters = highwayTravelMeters(route, restriction);
      final threshold = math.max(30, restriction.minimumAlignedTravelMeters);
      if (alignedMeters >= threshold) {
        return HighwayTravelMatch(
          restriction: restriction,
          alignedTravelMeters: alignedMeters,
        );
      }
    }
    return null;
  }

  static double highwayTravelMeters(
    List<LatLng> route,
    RouteRestriction restriction,
  ) {
    if (!isHighwayCorridor(restriction) || route.length < 2) return 0;
    var total = 0.0;
    for (var index = 1; index < route.length; index++) {
      final start = route[index - 1];
      final end = route[index];
      final length = _distanceMeters(start, end);
      if (length < 1) continue;
      final samples = math.max(1, (length / 12).ceil());
      for (var sample = 0; sample < samples; sample++) {
        final fraction = (sample + .5) / samples;
        final point = LatLng(
          start.latitude + (end.latitude - start.latitude) * fraction,
          start.longitude + (end.longitude - start.longitude) * fraction,
        );
        final closest = _closestCorridorSegment(point, restriction.areas);
        if (closest != null &&
            closest.distanceMeters <= restriction.bufferMeters &&
            _headingDifferenceDegrees(start, end, closest.start, closest.end) <=
                45) {
          total += length / samples;
        }
      }
    }
    return total;
  }

  /// Distance to the closest centreline of an active highway group. This is
  /// for a low-severity "already on a highway" warning; it is never an
  /// endpoint ban or confirmed driving violation.
  static double distanceToHighwayCorridorMeters(
    LatLng point,
    RouteRestriction restriction,
  ) {
    if (!isHighwayCorridor(restriction)) return double.infinity;
    return _closestCorridorSegment(point, restriction.areas)?.distanceMeters ??
        double.infinity;
  }

  static RouteRestrictionProximity pointProximity(
    LatLng point,
    List<RouteRestriction> restrictions, {
    String? preferredRestrictionId,
  }) {
    int? insideRestrictionIndex;
    int? nearestRestrictionIndex;
    double? nearestDistanceMeters;
    double? preferredDistanceMeters;

    for (var index = 0; index < restrictions.length; index++) {
      final restriction = restrictions[index];
      if (!isEnforcedPolygon(restriction)) continue;
      final distance = distanceToEnforcedPolygonMeters(point, restriction);
      if (!distance.isFinite) continue;
      if (preferredDistanceMeters == null &&
          preferredRestrictionId != null &&
          restriction.id == preferredRestrictionId) {
        preferredDistanceMeters = distance;
      }
      if (distance == 0 && insideRestrictionIndex == null) {
        insideRestrictionIndex = index;
      }
      if (nearestDistanceMeters == null || distance < nearestDistanceMeters) {
        nearestRestrictionIndex = index;
        nearestDistanceMeters = distance;
      }
    }

    return RouteRestrictionProximity(
      insideRestrictionIndex: insideRestrictionIndex,
      nearestRestrictionIndex: nearestRestrictionIndex,
      nearestDistanceMeters: nearestDistanceMeters,
      preferredDistanceMeters: preferredDistanceMeters,
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

  static _CorridorSegment? _closestCorridorSegment(
    LatLng point,
    List<List<LatLng>> areas,
  ) {
    _CorridorSegment? closest;
    for (final area in areas) {
      for (var index = 1; index < area.length; index++) {
        final distance = _pointToSegmentMeters(
          point,
          area[index - 1],
          area[index],
        );
        if (closest == null || distance < closest.distanceMeters) {
          closest = _CorridorSegment(
            start: area[index - 1],
            end: area[index],
            distanceMeters: distance,
          );
        }
      }
    }
    return closest;
  }

  static double _distanceMeters(LatLng start, LatLng end) {
    const metresPerDegree = 111320.0;
    final latitude = (start.latitude + end.latitude) / 2 * math.pi / 180;
    return math.sqrt(
      math.pow(
            (end.longitude - start.longitude) *
                metresPerDegree *
                math.cos(latitude),
            2,
          ) +
          math.pow((end.latitude - start.latitude) * metresPerDegree, 2),
    );
  }

  static double _headingDifferenceDegrees(
    LatLng start,
    LatLng end,
    LatLng corridorStart,
    LatLng corridorEnd,
  ) {
    double heading(LatLng a, LatLng b) =>
        math.atan2(
          b.latitude - a.latitude,
          (b.longitude - a.longitude) *
              math.cos((a.latitude + b.latitude) / 2 * math.pi / 180),
        ) *
        180 /
        math.pi;
    final difference =
        (heading(start, end) - heading(corridorStart, corridorEnd)).abs() % 180;
    return difference > 90 ? 180 - difference : difference;
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

class _CorridorSegment {
  const _CorridorSegment({
    required this.start,
    required this.end,
    required this.distanceMeters,
  });

  final LatLng start;
  final LatLng end;
  final double distanceMeters;
}
