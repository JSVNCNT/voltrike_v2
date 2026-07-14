import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'location_service.dart';
import 'roads_service.dart';
import 'routes_service.dart';
import 'traffic_service.dart';

/// ===========================================================================
/// Navigation Service
///
/// High-level navigation coordinator.
///
/// Uses:
/// - LocationService
/// - RoutesService
/// - TrafficService
/// - RoadsService
///
/// Passenger:
/// - Route Preview
///
/// Driver:
/// - Navigate to Passenger
/// - Navigate to Destination
/// - Live ETA
/// - Route Recalculation
/// ===========================================================================

class NavigationService {
  NavigationService._();

  static final NavigationService
      instance =
      NavigationService._();

  /// =========================================================================
  /// Start Navigation
  /// =========================================================================

  Future<void> startNavigation() async {
    await LocationService.instance
        .startTracking();
  }

  /// =========================================================================
  /// Stop Navigation
  /// =========================================================================


  Future<void> stopNavigation() async {
    await LocationService.instance
        .stopTracking();
  }

  /// =========================================================================
  /// Compute Route
  /// =========================================================================

  Future<Map<String, dynamic>?>
      computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return RoutesService.computeRoute(
      origin: origin,
      destination: destination,
    );
  }

  /// =========================================================================
  /// Traffic-Aware Route
  /// =========================================================================

  Future<Map<String, dynamic>?>
      computeTrafficRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return TrafficService
        .getTrafficRoute(
      origin: origin,
      destination: destination,
    );
  }

  /// =========================================================================
  /// Snap Driver Position to Road
  /// =========================================================================

  Future<LatLng?> snapDriverPosition(
    LatLng position,
  ) {
    return RoadsService.snapToRoad(
      position,
    );
  }

  /// =========================================================================
  /// Recalculate Route
  /// =========================================================================

  Future<Map<String, dynamic>?>
      recalculateRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return computeTrafficRoute(
      origin: origin,
      destination: destination,
    );
  }
}