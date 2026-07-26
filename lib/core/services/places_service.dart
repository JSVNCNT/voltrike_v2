import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../data/models/place_prediction.dart';
import '../config/api_keys.dart';

class PlacesService {
  PlacesService._();

  static const String _baseUrl = 'https://places.googleapis.com/v1';
  static const double searchRadiusMeters = 10000;
  static const Duration _timeout = Duration(seconds: 10);
  static final Map<String, Map<String, dynamic>> _detailsCache = {};

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
  };

  static Future<List<PlacePrediction>> searchPlaces(
    String query, {
    required double latitude,
    required double longitude,
    String? sessionToken,
  }) {
    return autocomplete(
      query,
      latitude: latitude,
      longitude: longitude,
      sessionToken: sessionToken,
    );
  }

  /// Returns only places within 10 km of the supplied live GPS/search origin.
  ///
  /// Google returns distanceMeters when `origin` is supplied. If an individual
  /// prediction omits it, details are resolved once and cached so the strict
  /// radius remains enforceable rather than relying on a soft location bias.
  static Future<List<PlacePrediction>> autocomplete(
    String query, {
    required double latitude,
    required double longitude,
    String? sessionToken,
  }) async {
    if (query.trim().isEmpty) return [];

    final body = <String, dynamic>{
      'input': query.trim(),
      'includedRegionCodes': ['ph'],
      'origin': {'latitude': latitude, 'longitude': longitude},
      'locationRestriction': {
        'circle': {
          'center': {'latitude': latitude, 'longitude': longitude},
          'radius': searchRadiusMeters,
        },
      },
      if (sessionToken != null && sessionToken.isNotEmpty)
        'sessionToken': sessionToken,
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl/places:autocomplete'),
          headers: {
            ..._headers,
            'X-Goog-FieldMask':
                'suggestions.placePrediction.placeId,'
                'suggestions.placePrediction.text,'
                'suggestions.placePrediction.structuredFormat,'
                'suggestions.placePrediction.distanceMeters',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) return [];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = decoded['suggestions'] as List? ?? const [];
    final predictions = <PlacePrediction>[];

    for (final item in suggestions) {
      if (item is! Map) continue;
      final raw = item['placePrediction'];
      if (raw is! Map) continue;
      final place = Map<String, dynamic>.from(raw);
      final placeId = place['placeId'] as String?;
      if (placeId == null || placeId.isEmpty) continue;
      final structured = place['structuredFormat'] as Map? ?? const {};
      final mainText = structured['mainText'] as Map? ?? const {};
      final secondaryText = structured['secondaryText'] as Map? ?? const {};
      final fullText = place['text'] as Map? ?? const {};
      var distance = (place['distanceMeters'] as num?)?.round();

      if (distance == null) {
        final details = await getPlaceDetails(placeId);
        final detailLatitude = (details?['latitude'] as num?)?.toDouble();
        final detailLongitude = (details?['longitude'] as num?)?.toDouble();
        if (detailLatitude != null && detailLongitude != null) {
          distance = proximityMeters(
            latitude,
            longitude,
            detailLatitude,
            detailLongitude,
          ).round();
        }
      }
      if (distance == null || !isWithinSearchRadius(distance)) continue;

      predictions.add(
        PlacePrediction(
          placeId: placeId,
          title: (mainText['text'] ?? fullText['text'] ?? 'Place').toString(),
          subtitle: secondaryText['text']?.toString(),
          distanceMeters: distance,
        ),
      );
    }

    predictions.sort(
      (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
    );
    return predictions;
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final cached = _detailsCache[placeId];
    if (cached != null) return Map<String, dynamic>.from(cached);

    final response = await http
        .get(
          Uri.parse('$_baseUrl/places/$placeId'),
          headers: {
            ..._headers,
            'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName = decoded['displayName'] as Map? ?? const {};
    final location = decoded['location'] as Map? ?? const {};
    final details = <String, dynamic>{
      'id': decoded['id'],
      'name': displayName['text']?.toString() ?? 'Selected place',
      'address': decoded['formattedAddress']?.toString() ?? '',
      'latitude': (location['latitude'] as num?)?.toDouble(),
      'longitude': (location['longitude'] as num?)?.toDouble(),
    };
    if (details['latitude'] == null || details['longitude'] == null) {
      return null;
    }
    _detailsCache[placeId] = details;
    return Map<String, dynamic>.from(details);
  }

  static bool isWithinSearchRadius(num distanceMeters) {
    return distanceMeters >= 0 && distanceMeters <= searchRadiusMeters;
  }

  static double proximityMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final startLatitude = _radians(latitudeA);
    final endLatitude = _radians(latitudeB);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(startLatitude) *
            math.cos(endLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
