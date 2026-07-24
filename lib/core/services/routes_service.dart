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
            'routes.polyline.encodedPolyline',
      };

  /// ==========================================================================
  /// Compute Route
  /// ==========================================================================
  static Future<RouteInfo?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
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
        route['distanceMeters'] as int? ?? 0;

    final durationString =
        route['duration'] as String? ?? '0s';

    final durationSeconds = int.tryParse(
          durationString.replaceAll('s', ''),
        ) ??
        0;

    final encodedPolyline =
        (route['polyline']
                as Map<String, dynamic>)['encodedPolyline']
            as String? ??
        '';

    return RouteInfo(
      distanceMeters: distanceMeters,
      distanceKm: distanceMeters / 1000,
      durationMinutes:
          (durationSeconds / 60).ceil(),
      encodedPolyline: encodedPolyline,
    );
  }
}