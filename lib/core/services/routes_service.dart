import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../data/models/route_info.dart';
import '../config/api_keys.dart';

class RoutesService {
  RoutesService._();

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,'
            'routes.duration,'
            'routes.polyline.encodedPolyline,'
            'routes.legs.steps.distanceMeters,'
            'routes.legs.steps.staticDuration,'
            'routes.legs.steps.startLocation,'
            'routes.legs.steps.endLocation,'
            'routes.legs.steps.polyline.encodedPolyline,'
            'routes.legs.steps.navigationInstruction',
      };

  /// ==========================================================================
  /// Compute Route
  /// ==========================================================================
  static Future<RouteInfo?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: _headers,
        body: jsonEncode({
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
          'routingPreference': 'TRAFFIC_AWARE',
          'computeAlternativeRoutes': false,
        }),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final json =
          jsonDecode(response.body) as Map<String, dynamic>;

      final routes = json['routes'] as List?;

      if (routes == null || routes.isEmpty) {
        return null;
      }

      final route =
          routes.first as Map<String, dynamic>;

      final distanceMeters =
          (route['distanceMeters'] as num?)?.round() ?? 0;

      final durationString =
          route['duration'] as String? ?? '0s';

      final durationSeconds = _durationSeconds(durationString);

      final encodedPolyline =
          (route['polyline']
                  as Map<String, dynamic>?)?['encodedPolyline']
              as String? ??
          '';

      final List<RouteStep> steps = [];

      final legs =
          route['legs'] as List? ?? [];

      for (final leg in legs) {
        final legMap =
            leg as Map<String, dynamic>;

        final rawSteps =
            legMap['steps'] as List? ?? [];

        for (final raw in rawSteps) {
          final step =
              raw as Map<String, dynamic>;

          final navigation =
              step['navigationInstruction'] as Map<String, dynamic>? ?? {};

          final start =
              step['startLocation'] as Map<String, dynamic>? ?? {};

          final end =
              step['endLocation'] as Map<String, dynamic>? ?? {};

          final startLatLng =
              start['latLng'] as Map<String, dynamic>? ?? {};

          final endLatLng =
              end['latLng'] as Map<String, dynamic>? ?? {};

          final polyline =
              step['polyline'] as Map<String, dynamic>? ?? {};

          final staticDuration = step['staticDuration'] as String? ?? '0s';

          steps.add(
            RouteStep(
              instruction: navigation['instructions'] as String? ?? '',
              maneuver: navigation['maneuver'] as String? ?? '',
              distanceMeters:
                  (step['distanceMeters'] as num?)?.round() ?? 0,
              durationSeconds: _durationSeconds(staticDuration),
              startLocation: LatLng(
                (startLatLng['latitude'] as num?)?.toDouble() ?? 0,
                (startLatLng['longitude'] as num?)?.toDouble() ?? 0,
              ),
              endLocation: LatLng(
                (endLatLng['latitude'] as num?)?.toDouble() ?? 0,
                (endLatLng['longitude'] as num?)?.toDouble() ?? 0,
              ),
              encodedPolyline: polyline['encodedPolyline'] as String? ?? '',
            ),
          );
        }
      }

      return RouteInfo(
        distanceMeters: distanceMeters,
        distanceKm: distanceMeters / 1000,
        durationMinutes:
            (durationSeconds / 60).ceil(),
        encodedPolyline:
            encodedPolyline,
        steps: steps,
      );
    } on FormatException {
      return null;
    } on http.ClientException {
      return null;
    }
  }

  static int _durationSeconds(String value) {
    return (double.tryParse(value.replaceAll('s', '')) ?? 0).round();
  }
}
