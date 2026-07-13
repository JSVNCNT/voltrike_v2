import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

class PlacesService {
  PlacesService._();

  static const String _baseUrl =
      'https://places.googleapis.com/v1';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key':
            ApiKeys.googleMapsApiKey,
      };

  //==========================================================================
  // Autocomplete
  //==========================================================================

  static Future<List<Map<String, dynamic>>>
      autocomplete(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final uri = Uri.parse(
      '$_baseUrl/places:autocomplete',
    );

    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'input': query,
      }),
    );

    if (response.statusCode != 200) {
      return [];
    }

    final data =
        jsonDecode(response.body);

    final suggestions =
        data['suggestions'] as List? ?? [];

    return suggestions
        .map<Map<String, dynamic>>(
      (item) {
        final place =
            item['placePrediction'];

        return {
          'placeId':
              place['placeId'],
          'text': place['text']
              ['text'],
        };
      },
    ).toList();
  }

  //==========================================================================
  // Place Details
  //==========================================================================

  static Future<Map<String, dynamic>?>
      getPlaceDetails(
    String placeId,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/places/$placeId',
    );

    final response = await http.get(
      uri,
      headers: {
        ..._headers,
        'X-Goog-FieldMask':
            'id,displayName,formattedAddress,location',
      },
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data =
        jsonDecode(response.body);

    return {
      'id': data['id'],
      'name': data['displayName']
          ['text'],
      'address':
          data['formattedAddress'],
      'latitude':
          data['location']['latitude'],
      'longitude':
          data['location']['longitude'],
    };
  }
}