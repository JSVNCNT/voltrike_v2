import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../data/models/route_info.dart';
import 'location_service.dart';
import 'polyline_service.dart';
import 'roads_service.dart';
import 'routes_service.dart';

/// ===========================================================================
/// Navigation Service
///
/// High-level coordinator used by the Driver app.
///
/// Coordinates:
/// • LocationService
/// • RoutesService
/// • RoadsService
/// • PolylineService
/// ===========================================================================
class NavigationService {
  NavigationService._();

  static final NavigationService instance =
      NavigationService._();

  StreamSubscription<Position>? _liveLocationSubscription;
  Position? _liveLocation;

  Position? get liveLocation => _liveLocation;

  /// Accepts the active driver's live GPS source without coupling navigation
  /// to a particular transport (local GPS, RTDB relay, or simulator).
  void bindLiveLocation(Stream<Position> locations) {
    _liveLocationSubscription?.cancel();
    _liveLocationSubscription = locations.listen((position) {
      _liveLocation = position;
    });
  }

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

  Future<Position> currentLocation() {
    return LocationService.instance.getCurrentLocation();
  }

  //==========================================================================
  // Live Location
  //==========================================================================

  Stream<Position> get locationStream {
    return LocationService.instance.locationStream;
  }

  //==========================================================================
  // Start Navigation
  //==========================================================================

  Future<void> startNavigation() async {
    await ensurePermission();
    await LocationService.instance.startTracking();
  }

  //==========================================================================
  // Stop Navigation
  //==========================================================================

  Future<void> stopNavigation() {
    return LocationService.instance.stopTracking();
  }

  //==========================================================================
  // Compute Route
  //==========================================================================

  /// Retrieves the canonical Google Routes result used by navigation sessions.
  ///
  /// Route retrieval and parsing remain the responsibility of [RoutesService].
  /// The map-shaped methods below are retained temporarily for existing driver
  /// and passenger callers while those screens are moved to [RouteInfo].
  Future<RouteInfo?> computeRouteInfo({
    required LatLng origin,
    required LatLng destination,
  }) {
    return RoutesService.computeRoute(
      origin: origin,
      destination: destination,
    );
  }

  Future<Map<String, dynamic>?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final route = await computeRouteInfo(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      return null;
    }

    return _toLegacyRouteMap(route);
  }

  //==========================================================================
  // Traffic Route
  //==========================================================================

  Future<Map<String, dynamic>?> computeTrafficRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return computeRoute(
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
    return PolylineService.decodePolyline(
      encodedPolyline,
    );
  }

  //==========================================================================
  // Snap To Road
  //==========================================================================

  Future<LatLng?> snapToRoad(
    LatLng position,
  ) {
    return RoadsService.snapToRoad(position);
  }

  //==========================================================================
  // Recalculate Route
  //==========================================================================

  Future<Map<String, dynamic>?> recalculateRoute({
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
    return route['distanceMeters'] as int? ?? 0;
  }

  double distanceKm(
    Map<String, dynamic> route,
  ) {
    return (route['distanceKm'] as num?)?.toDouble() ??
        (distanceMeters(route) / 1000.0);
  }

  int durationMinutes(
    Map<String, dynamic> route,
  ) {
    return route['durationMinutes'] as int? ?? 0;
  }

  String duration(
    Map<String, dynamic> route,
  ) {
    return route['duration'] as String? ??
        '${durationMinutes(route)} mins';
  }

  String encodedPolyline(
    Map<String, dynamic> route,
  ) {
    return route['encodedPolyline'] as String? ?? '';
  }

  Map<String, dynamic> _toLegacyRouteMap(RouteInfo route) {
    return {
      'distanceMeters': route.distanceMeters,
      'distanceKm': route.distanceKm,
      'duration': '${route.durationMinutes} mins',
      'durationMinutes': route.durationMinutes,
      'encodedPolyline': route.encodedPolyline,
    };
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  Future<void> dispose() async {
    await _liveLocationSubscription?.cancel();
    _liveLocationSubscription = null;
    _liveLocation = null;
    await stopNavigation();
  }
}
