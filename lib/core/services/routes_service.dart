import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

class RoutesService {
  RoutesService._();

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key':
            ApiKeys.googleMapsApiKey,
        'X-Goog-FieldMask':
            'routes.distanceMeters,'
            'routes.duration,'
            'routes.polyline.encodedPolyline,'
            'routes.legs,'
            'routes.travelAdvisory',
      };

  /// ==========================================================================
  /// Compute Route
  /// ==========================================================================

  static Future<Map<String, dynamic>?>
      computeRoute({
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
        'routingPreference':
            'TRAFFIC_AWARE',
        'computeAlternativeRoutes': true,
      }),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data =
        jsonDecode(response.body);

    if (data['routes'] == null ||
        data['routes'].isEmpty) {
      return null;
    }

    final route = data['routes'][0];

    return {
      'distanceMeters':
          route['distanceMeters'] ?? 0,

      'duration':
          route['duration'] ?? '',

      'encodedPolyline':
          route['polyline']
              ['encodedPolyline'],

      'raw': route,
    };
  }
}