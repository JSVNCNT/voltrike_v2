import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

class GeocodingService {
  GeocodingService._();

  static const _baseUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// ==========================================================================
  /// Address -> Coordinates
  /// ==========================================================================

  static Future<LatLng?> addressToLatLng(
    String address,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl?address=${Uri.encodeComponent(address)}'
      '&key=${ApiKeys.googleMapsApiKey}',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return null;
    }

    final data =
        jsonDecode(response.body);

    if (data['results'] == null ||
        data['results'].isEmpty) {
      return null;
    }

    final location =
        data['results'][0]['geometry']['location'];

    return LatLng(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
  }

  /// ==========================================================================
  /// Coordinates -> Address
  /// ==========================================================================

  static Future<String?> latLngToAddress(
    LatLng latLng,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl?latlng=${latLng.latitude},${latLng.longitude}'
      '&key=${ApiKeys.googleMapsApiKey}',
    );

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      return null;
    }

    final data =
        jsonDecode(response.body);

    if (data['results'] == null ||
        data['results'].isEmpty) {
      return null;
    }

    return data['results'][0]
        ['formatted_address'];
  }
}