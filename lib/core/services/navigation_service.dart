import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'location_service.dart';
import 'polyline_service.dart';
import 'roads_service.dart';
import 'routes_service.dart';
import 'traffic_service.dart';

/// ===========================================================================
/// Navigation Service
///
/// High-level coordinator used by the Driver app.
///
/// Coordinates:
/// • LocationService
/// • RoutesService
/// • TrafficService
/// • RoadsService
/// • PolylineService
/// ===========================================================================
class NavigationService {
  NavigationService._();

  static final NavigationService instance =
      NavigationService._();

  //==========================================================================
  // Permissions
  //==========================================================================

  Future<void> ensurePermission() {
    return LocationService.instance
        .ensurePermission();
  }

  //==========================================================================
  // Current Location
  //==========================================================================

  Future<Position> currentLocation() async {
    return await Geolocator
        .getCurrentPosition();
  }

  //==========================================================================
  // Live Location
  //==========================================================================

  Stream<Position> get locationStream {
    return LocationService.instance
        .locationStream;
  }

  //==========================================================================
  // Start Navigation
  //==========================================================================

  Future<void> startNavigation() async {
    await ensurePermission();

    await LocationService.instance
        .startTracking();
  }

  //==========================================================================
  // Stop Navigation
  //==========================================================================

  Future<void> stopNavigation() {
    return LocationService.instance
        .stopTracking();
  }

  //==========================================================================
  // Compute Route
  //==========================================================================

  Future<Map<String, dynamic>?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return RoutesService.computeRoute(
      origin: origin,
      destination: destination,
    );
  }

  //==========================================================================
  // Traffic Route
  //==========================================================================

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

  //==========================================================================
  // Decode Polyline
  //==========================================================================

  List<LatLng> decodePolyline(
    String encodedPolyline,
  ) {
    return PolylineService
        .decodePolyline(
      encodedPolyline,
    );
  }

  //==========================================================================
  // Snap To Road
  //==========================================================================

  Future<LatLng?> snapToRoad(
    LatLng position,
  ) {
    return RoadsService.snapToRoad(
      position,
    );
  }

  //==========================================================================
  // Recalculate Route
  //==========================================================================

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

  //==========================================================================
  // Helpers
  //==========================================================================

  int distanceMeters(
    Map<String, dynamic> route,
  ) {
    return (route['distanceMeters']
            as int?) ??
        0;
  }

  String duration(
    Map<String, dynamic> route,
  ) {
    return (route['duration']
            as String?) ??
        '';
  }

  String encodedPolyline(
    Map<String, dynamic> route,
  ) {
    return (route['encodedPolyline']
            as String?) ??
        '';
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await stopNavigation();
  }
}