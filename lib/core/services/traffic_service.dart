import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  static Future<Map<String, dynamic>?>
      getTrafficRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return RoutesService.computeRoute(
      origin: origin,
      destination: destination,
    );
  }

  /// =========================================================================
  /// ETA
  /// =========================================================================

  static Future<String?> getEta({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route =
        await getTrafficRoute(
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
    final route =
        await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['distanceMeters'] as int?;
  }

  /// =========================================================================
  /// Encoded Polyline
  /// =========================================================================

  static Future<String?> getPolyline({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route =
        await getTrafficRoute(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return route['encodedPolyline']
        as String?;
  }
}