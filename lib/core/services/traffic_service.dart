import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import 'routes_service.dart';

/// ===========================================================================
/// Traffic Service
///
/// Handles traffic-aware route computation.
///
/// Uses Google Routes API internally.
///
/// Passenger:
/// - Estimated travel time
/// - Alternate routes
///
/// Driver:
/// - Live ETA
/// - Route recalculation
/// ===========================================================================
class TrafficService {
  TrafficService._();

  /// =========================================================================
  /// Get Traffic-Aware Route
  /// =========================================================================

  static Future<Map<String, dynamic>?> getTrafficRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await RoutesService.computeRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return {
      'distanceMeters': route.distanceMeters,
      'distanceKm': route.distanceKm,
      'duration': '${route.durationMinutes} mins',
      'durationMinutes': route.durationMinutes,
      'encodedPolyline': route.encodedPolyline,
    };
  }

  /// =========================================================================
  /// ETA
  /// =========================================================================

  static Future<String?> getEta({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['duration'] as String?;
  }

  /// =========================================================================
  /// Distance
  /// =========================================================================

  static Future<int?> getDistanceMeters({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['distanceMeters'] as int?;
  }

  /// =========================================================================
  /// Distance (Kilometers)
  /// =========================================================================

  static Future<double?> getDistanceKm({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return (route['distanceKm'] as num?)?.toDouble();
  }

  /// =========================================================================
  /// Duration (Minutes)
  /// =========================================================================

  static Future<int?> getDurationMinutes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['durationMinutes'] as int?;
  }

  /// =========================================================================
  /// Encoded Polyline
  /// =========================================================================

  static Future<String?> getPolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['encodedPolyline'] as String?;
  }
}
