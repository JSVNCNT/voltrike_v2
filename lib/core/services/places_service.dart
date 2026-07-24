import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/place_prediction.dart';
import '../config/api_keys.dart';

class PlacesService {
  PlacesService._();

  static const String _baseUrl =
      'https://places.googleapis.com/v1';

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
      };

  //==========================================================================
  // Search Places
  //==========================================================================

  static Future<List<PlacePrediction>> searchPlaces(
    String query, {
    double? latitude,
    double? longitude,
  }) {
    return autocomplete(
      query,
      latitude: latitude,
      longitude: longitude,
    );
  }

  //==========================================================================
  // Autocomplete
  //==========================================================================

  static Future<List<PlacePrediction>> autocomplete(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final body = <String, dynamic>{
      'input': query,

      // Restrict results to the Philippines
      'includedRegionCodes': ['ph'],
    };

    // Prefer nearby places if current location is available
    if (latitude != null && longitude != null) {
      body['locationBias'] = {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': 10000.0, // 10 km
        },
      };
    }

    final response = await http.post(
      Uri.parse(
        '$_baseUrl/places:autocomplete',
      ),
      headers: _headers,
      body: jsonEncode(body),
    );

    debugPrint('==========================');
    debugPrint('Places Autocomplete');
    debugPrint('Query: $query');
    debugPrint('Latitude: $latitude');
    debugPrint('Longitude: $longitude');
    debugPrint('Request Body: ${jsonEncode(body)}');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response: ${response.body}');
    debugPrint('==========================');

    if (response.statusCode != 200) {
      return [];
    }

    final json =
        jsonDecode(response.body)
            as Map<String, dynamic>;

    final suggestions =
        json['suggestions'] as List? ?? [];

    return suggestions
        .map<PlacePrediction>((item) {
      final place =
          item['placePrediction']
              as Map<String, dynamic>;

      return PlacePrediction(
        placeId:
            place['placeId'] as String,
        title:
            place['text']['text']
                as String,
        subtitle:
            place['text']
                ['secondaryText'] as String?,
      );
    }).toList();
  }

  //==========================================================================
  // Place Details
  //==========================================================================

  static Future<Map<String, dynamic>?>
      getPlaceDetails(
    String placeId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$_baseUrl/places/$placeId',
      ),
      headers: {
        ..._headers,
        'X-Goog-FieldMask':
            'id,displayName,formattedAddress,location',
      },
    );

    debugPrint('==========================');
    debugPrint('Place Details');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response: ${response.body}');
    debugPrint('==========================');

    if (response.statusCode != 200) {
      return null;
    }

    final json =
        jsonDecode(response.body)
            as Map<String, dynamic>;

    return {
      'id': json['id'],
      'name':
          json['displayName']['text'],
      'address':
          json['formattedAddress'],
      'latitude':
          json['location']['latitude'],
      'longitude':
          json['location']['longitude'],
    };
  }
}