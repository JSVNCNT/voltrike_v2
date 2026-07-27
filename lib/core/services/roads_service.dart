import 'dart:convert';

import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

class RoadsService {
  RoadsService._();

  static const String _baseUrl =
      'https://roads.googleapis.com/v1/snapToRoads';

  /// ==========================================================================
  /// Snap to Road
  /// ==========================================================================
  ///
  /// Returns the nearest road position for a GPS coordinate.
  ///
  static Future<LatLng?> snapToRoad(
    LatLng position,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl'
      '?path=${position.latitude},${position.longitude}'
      '&interpolate=false'
      '&key=${ApiKeys.googleMapsApiKey}',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return null;
    }

    final data =
        jsonDecode(response.body);

    final points =
        data['snappedPoints'] as List?;

    if (points == null || points.isEmpty) {
      return null;
    }

    final location =
        points.first['location'];

    return LatLng(
      (location['latitude'] as num)
          .toDouble(),
      (location['longitude'] as num)
          .toDouble(),
    );
  }
}
