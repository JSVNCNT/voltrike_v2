import 'dart:convert';

import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:http/http.dart' as http;

import '../../data/models/route_info.dart';
import '../config/api_keys.dart';
import 'polyline_service.dart';
import 'route_restriction_service.dart';

class RoutesService {
  RoutesService._();

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,'
            'routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,'
            'routes.legs.steps.startLocation,routes.legs.steps.endLocation,'
            'routes.legs.steps.polyline.encodedPolyline,'
            'routes.legs.steps.navigationInstruction',
      };

  /// Requests Google alternatives, then selects the first route that does not
  /// enter a developer-defined prohibited highway, crossing, or service area.
  static Future<RouteInfo?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: _headers,
        body: jsonEncode({
          'origin': {'location': {'latLng': {'latitude': origin.latitude, 'longitude': origin.longitude}}},
          'destination': {'location': {'latLng': {'latitude': destination.latitude, 'longitude': destination.longitude}}},
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
          'computeAlternativeRoutes': true,
        }),
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawRoutes = decoded['routes'] as List?;
      if (rawRoutes == null || rawRoutes.isEmpty) return null;

      final restrictions = RouteRestrictionService.instance;
      for (final raw in rawRoutes) {
        final route = _parseRoute(raw as Map<String, dynamic>);
        final conflict = await restrictions.routeConflict(
          PolylineService.decodePolyline(route.encodedPolyline),
        );
        if (conflict == null) return route;
        restrictions.markConflict(conflict);
      }
      // Do not direct a passenger or driver through a configured restriction
      // when Google has no safe alternative.
      return null;
    } on FormatException {
      return null;
    } on http.ClientException {
      return null;
    }
  }

  static RouteInfo _parseRoute(Map<String, dynamic> route) {
    final distanceMeters = (route['distanceMeters'] as num?)?.round() ?? 0;
    final durationSeconds = _durationSeconds(route['duration'] as String? ?? '0s');
    final encodedPolyline =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline'] as String? ?? '';
    final steps = <RouteStep>[];
    for (final leg in route['legs'] as List? ?? const []) {
      for (final rawStep in (leg as Map<String, dynamic>)['steps'] as List? ?? const []) {
        final step = rawStep as Map<String, dynamic>;
        final navigation = step['navigationInstruction'] as Map<String, dynamic>? ?? const {};
        final start = (step['startLocation'] as Map<String, dynamic>?)?['latLng'] as Map<String, dynamic>? ?? const {};
        final end = (step['endLocation'] as Map<String, dynamic>?)?['latLng'] as Map<String, dynamic>? ?? const {};
        final polyline = step['polyline'] as Map<String, dynamic>? ?? const {};
        steps.add(RouteStep(
          instruction: navigation['instructions'] as String? ?? '',
          maneuver: navigation['maneuver'] as String? ?? '',
          distanceMeters: (step['distanceMeters'] as num?)?.round() ?? 0,
          durationSeconds: _durationSeconds(step['staticDuration'] as String? ?? '0s'),
          startLocation: LatLng((start['latitude'] as num?)?.toDouble() ?? 0, (start['longitude'] as num?)?.toDouble() ?? 0),
          endLocation: LatLng((end['latitude'] as num?)?.toDouble() ?? 0, (end['longitude'] as num?)?.toDouble() ?? 0),
          encodedPolyline: polyline['encodedPolyline'] as String? ?? '',
        ));
      }
    }
    return RouteInfo(
      distanceMeters: distanceMeters,
      distanceKm: distanceMeters / 1000,
      durationMinutes: (durationSeconds / 60).ceil(),
      encodedPolyline: encodedPolyline,
      steps: steps,
    );
  }

  static int _durationSeconds(String value) =>
      (double.tryParse(value.replaceAll('s', '')) ?? 0).round();
}
