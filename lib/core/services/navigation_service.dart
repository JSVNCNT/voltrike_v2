import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../data/models/route_info.dart';
import '../config/api_keys.dart';

/// ============================================================================
/// Routes Service
///
/// Google Routes API wrapper.
///
/// Responsibilities
/// ----------------------------------------------------------------------------
/// • Compute routes
/// • Parse responses
/// • Parse route steps
/// • Parse navigation instructions
/// • Parse polylines
/// • Parse durations
///
/// NOTE:
/// This service only communicates with the Google Routes API.
/// It contains no UI logic.
/// ============================================================================
class RoutesService {
  RoutesService._();

  //==========================================================================
  // Constants
  //==========================================================================

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  //==========================================================================
  // Field Masks
  //==========================================================================

  /// Basic route information.
  static const String _basicFieldMask =
      'routes.distanceMeters,'
      'routes.duration,'
      'routes.polyline.encodedPolyline';

  /// Full navigation information.
  static const String _navigationFieldMask =
      'routes.distanceMeters,'
      'routes.duration,'
      'routes.polyline.encodedPolyline,'
      'routes.legs.steps';

  //==========================================================================
  // Headers
  //==========================================================================

  static Map<String, String> _headers(
    String fieldMask,
  ) {
    return {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
      'X-Goog-FieldMask': fieldMask,
    };
  }

  //==========================================================================
  // Request Body
  //==========================================================================

  static Map<String, dynamic> _requestBody({
    required LatLng origin,
    required LatLng destination,
    bool trafficAware = true,
    bool alternatives = false,
  }) {
    return {
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
        },
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
        },
      },
      'travelMode': 'DRIVE',
      'routingPreference': trafficAware
          ? 'TRAFFIC_AWARE'
          : 'TRAFFIC_UNAWARE',
      'computeAlternativeRoutes': alternatives,
    };
  }

  //==========================================================================
  // HTTP
  //==========================================================================

  static Future<http.Response> _post({
    required LatLng origin,
    required LatLng destination,
    String fieldMask = _navigationFieldMask,
    bool trafficAware = true,
    bool alternatives = false,
  }) {
    return http.post(
      Uri.parse(_baseUrl),
      headers: _headers(fieldMask),
      body: jsonEncode(
        _requestBody(
          origin: origin,
          destination: destination,
          trafficAware: trafficAware,
          alternatives: alternatives,
        ),
      ),
    );
  }

  //==========================================================================
  // Helpers
  //==========================================================================

  static int _parseDurationSeconds(
    String duration,
  ) {
    return int.tryParse(
          duration.replaceAll('s', ''),
        ) ??
        0;
  }

  static int _parseDurationMinutes(
    String duration,
  ) {
    return (_parseDurationSeconds(duration) / 60)
        .ceil();
  }

  static LatLng _parseLatLng(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return const LatLng(0, 0);
    }

    return LatLng(
      (json['latitude'] as num?)?.toDouble() ??
          0,
      (json['longitude'] as num?)?.toDouble() ??
          0,
    );
  }

  static String _parsePolyline(
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return '';
    }

    return json['encodedPolyline'] as String? ??
        '';
  }

  static List<dynamic> _parseRoutes(
    Map<String, dynamic> json,
  ) {
    return json['routes'] as List? ?? [];
  }

  static List<dynamic> _parseLegs(
    Map<String, dynamic> route,
  ) {
    return route['legs'] as List? ?? [];
  }

  static List<dynamic> _parseSteps(
    Map<String, dynamic> leg,
  ) {
    return leg['steps'] as List? ?? [];
  }

    //==========================================================================
  // Route Parsing
  //==========================================================================

  static RouteStep _parseStep(
    Map<String, dynamic> step,
  ) {
    final navigation =
        step['navigationInstruction']
                as Map<String, dynamic>? ??
            {};

    final start =
        (step['startLocation']
                    as Map<String, dynamic>?)?[
                'latLng']
            as Map<String, dynamic>?;

    final end =
        (step['endLocation']
                    as Map<String, dynamic>?)?[
                'latLng']
            as Map<String, dynamic>?;

    final polyline =
        step['polyline']
            as Map<String, dynamic>?;

    final duration =
        step['staticDuration'] as String? ??
            '0s';

    return RouteStep(
      instruction:
          navigation['instructions']
                  as String? ??
              '',
      maneuver:
          navigation['maneuver']
                  as String? ??
              '',
      distanceMeters:
          step['distanceMeters']
                  as int? ??
              0,
      durationSeconds:
          _parseDurationSeconds(duration),
      startLocation:
          _parseLatLng(start),
      endLocation:
          _parseLatLng(end),
      encodedPolyline:
          _parsePolyline(polyline),
    );
  }

  //==========================================================================
  // Leg Parsing
  //==========================================================================

  static List<RouteStep> _parseLeg(
    Map<String, dynamic> leg,
  ) {
    final parsed = <RouteStep>[];

    for (final raw in _parseSteps(leg)) {
      parsed.add(
        _parseStep(
          raw as Map<String, dynamic>,
        ),
      );
    }

    return parsed;
  }

  //==========================================================================
  // Route Parsing
  //==========================================================================

  static RouteInfo _parseRoute(
    Map<String, dynamic> route,
  ) {
    final distanceMeters =
        route['distanceMeters'] as int? ?? 0;

    final duration =
        route['duration'] as String? ??
            '0s';

    final polyline =
        route['polyline']
            as Map<String, dynamic>?;

    final steps = <RouteStep>[];

    for (final rawLeg in _parseLegs(route)) {
      steps.addAll(
        _parseLeg(
          rawLeg as Map<String, dynamic>,
        ),
      );
    }

    return RouteInfo(
      distanceMeters: distanceMeters,
      distanceKm:
          distanceMeters / 1000,
      durationMinutes:
          _parseDurationMinutes(
              duration),
      encodedPolyline:
          _parsePolyline(polyline),
      steps: steps,
    );
  }

  //==========================================================================
  // Response Parsing
  //==========================================================================

  static RouteInfo? _parseResponse(
    http.Response response,
  ) {
    if (response.statusCode != 200) {
      return null;
    }

    final json =
        jsonDecode(response.body)
            as Map<String, dynamic>;

    final routes =
        _parseRoutes(json);

    if (routes.isEmpty) {
      return null;
    }

    return _parseRoute(
      routes.first
          as Map<String, dynamic>,
    );
  }

    //==========================================================================
  // Public API
  //==========================================================================

  /// Computes a driving route using live traffic.
  static Future<RouteInfo?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await _post(
        origin: origin,
        destination: destination,
        fieldMask: _navigationFieldMask,
        trafficAware: true,
      );

      return _parseResponse(response);
    } catch (_) {
      return null;
    }
  }

  /// Computes a driving route without live traffic.
  static Future<RouteInfo?> computeTrafficUnawareRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await _post(
        origin: origin,
        destination: destination,
        fieldMask: _navigationFieldMask,
        trafficAware: false,
      );

      return _parseResponse(response);
    } catch (_) {
      return null;
    }
  }

  /// Computes alternative routes.
  ///
  /// Currently returns the first (recommended) route.
  static Future<RouteInfo?> computeAlternativeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await _post(
        origin: origin,
        destination: destination,
        fieldMask: _navigationFieldMask,
        trafficAware: true,
        alternatives: true,
      );

      return _parseResponse(response);
    } catch (_) {
      return null;
    }
  }

  /// Alias used by the navigation engine.
  static Future<RouteInfo?> computeNavigationRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return computeRoute(
      origin: origin,
      destination: destination,
    );
  }

    //==========================================================================
  // Navigation Helpers
  //==========================================================================

  /// Refreshes the current route using live traffic.
  static Future<RouteInfo?> refreshRoute({
    required LatLng currentLocation,
    required LatLng destination,
  }) {
    return computeRoute(
      origin: currentLocation,
      destination: destination,
    );
  }

  /// Recomputes a route after the driver goes off-route.
  static Future<RouteInfo?> reroute({
    required LatLng currentLocation,
    required LatLng destination,
  }) {
    return computeRoute(
      origin: currentLocation,
      destination: destination,
    );
  }

  /// Returns the decoded polyline for rendering on Google Maps.
  static List<LatLng> decodePolyline(
    RouteInfo route,
  ) {
    return _decodePolyline(
      route.encodedPolyline,
    );
  }

  //==========================================================================
  // Polyline Decoder
  //==========================================================================

  static List<LatLng> _decodePolyline(
    String encoded,
  ) {
    if (encoded.isEmpty) {
      return [];
    }

    final points = <LatLng>[];

    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;

      while (true) {
        final byte =
            encoded.codeUnitAt(index++) - 63;
        result |=
            (byte & 0x1f) << shift;
        shift += 5;
        if (byte < 0x20) break;
      }

      final deltaLat =
          (result & 1) != 0
              ? ~(result >> 1)
              : (result >> 1);

      lat += deltaLat;

      shift = 0;
      result = 0;

      while (true) {
        final byte =
            encoded.codeUnitAt(index++) - 63;
        result |=
            (byte & 0x1f) << shift;
        shift += 5;
        if (byte < 0x20) break;
      }

      final deltaLng =
          (result & 1) != 0
              ? ~(result >> 1)
              : (result >> 1);

      lng += deltaLng;

      points.add(
        LatLng(
          lat / 1E5,
          lng / 1E5,
        ),
      );
    }

    return points;
  }

  //==========================================================================
  // Convenience Helpers
  //==========================================================================

  static double distanceKm(
    RouteInfo route,
  ) {
    return route.distanceKm;
  }

  static int distanceMeters(
    RouteInfo route,
  ) {
    return route.distanceMeters;
  }

  static int durationMinutes(
    RouteInfo route,
  ) {
    return route.durationMinutes;
  }

  static List<RouteStep> steps(
    RouteInfo route,
  ) {
    return route.steps;
  }

  static bool hasSteps(
    RouteInfo route,
  ) {
    return route.steps.isNotEmpty;
  }

  static RouteStep? firstStep(
    RouteInfo route,
  ) {
    if (route.steps.isEmpty) {
      return null;
    }

    return route.steps.first;
  }

  static RouteStep? lastStep(
    RouteInfo route,
  ) {
    if (route.steps.isEmpty) {
      return null;
    }

    return route.steps.last;
  }
}

  //==========================================================================
  // Diagnostics
  //==========================================================================

  /// Enables or disables RoutesService logging.
  static bool enableLogging = false;

  static void _log(Object message) {
    if (!enableLogging) return;

    // ignore: avoid_print
    print('[RoutesService] $message');
  }

  static void logRoute(RouteInfo route) {
    _log('----------------------------------------');
    _log('Distance : ${route.distanceKm.toStringAsFixed(2)} km');
    _log('Duration : ${route.durationMinutes} min');
    _log('Steps    : ${route.steps.length}');
    _log('----------------------------------------');
  }

  static void logSteps(RouteInfo route) {
    if (!enableLogging) return;

    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];

      _log(
        '#${i + 1} '
        '${step.instruction} '
        '(${step.distanceMeters}m)',
      );
    }
  }

  //==========================================================================
  // Validation
  //==========================================================================

  static bool isValid(RouteInfo? route) {
    if (route == null) return false;

    if (route.distanceMeters <= 0) return false;

    if (route.encodedPolyline.isEmpty) return false;

    return true;
  }

  static bool hasNavigation(RouteInfo route) {
    return route.steps.isNotEmpty;
  }

  //==========================================================================
  // Testing Helpers
  //==========================================================================

  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.google.com'),
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }