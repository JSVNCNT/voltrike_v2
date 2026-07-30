import 'dart:collection';
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
  static const Duration _detailsCacheTtl = Duration(minutes: 10);
  static const int _maximumDetailsCacheEntries = 64;
  static const int _maximumDetailsConcurrency = 4;
  static final LinkedHashMap<String, _CachedPlaceDetails> _detailsCache =
      LinkedHashMap<String, _CachedPlaceDetails>();
  static final Map<String, Future<Map<String, dynamic>?>> _detailsInFlight =
      <String, Future<Map<String, dynamic>?>>{};

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
    final missingDistances = <_PendingPlacePrediction>[];

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
      final distance = (place['distanceMeters'] as num?)?.round();

      final pending = _PendingPlacePrediction(
        placeId: placeId,
        title: (mainText['text'] ?? fullText['text'] ?? 'Place').toString(),
        subtitle: secondaryText['text']?.toString(),
      );
      if (distance == null) {
        missingDistances.add(pending);
      } else if (isWithinSearchRadius(distance)) {
        predictions.add(pending.toPrediction(distance));
      }
    }

    for (
      var start = 0;
      start < missingDistances.length;
      start += _maximumDetailsConcurrency
    ) {
      final end = math.min(
        start + _maximumDetailsConcurrency,
        missingDistances.length,
      );
      final resolved = await Future.wait(
        missingDistances
            .sublist(start, end)
            .map(
              (pending) => _resolvePredictionDistance(
                pending,
                latitude: latitude,
                longitude: longitude,
              ),
            ),
      );
      predictions.addAll(resolved.whereType<PlacePrediction>());
    }

    predictions.sort(
      (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
    );
    return predictions;
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final cached = _detailsCache.remove(placeId);
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <= _detailsCacheTtl) {
      _detailsCache[placeId] = cached;
      return Map<String, dynamic>.from(cached.details);
    }

    final existing = _detailsInFlight[placeId];
    if (existing != null) return existing;
    final request = _fetchPlaceDetails(placeId);
    _detailsInFlight[placeId] = request;
    try {
      return await request;
    } finally {
      if (identical(_detailsInFlight[placeId], request)) {
        _detailsInFlight.remove(placeId);
      }
    }
  }

  static Future<Map<String, dynamic>?> _fetchPlaceDetails(
    String placeId,
  ) async {
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
    _detailsCache[placeId] = _CachedPlaceDetails(
      details: Map<String, dynamic>.unmodifiable(details),
      createdAt: DateTime.now(),
    );
    while (_detailsCache.length > _maximumDetailsCacheEntries) {
      _detailsCache.remove(_detailsCache.keys.first);
    }
    return Map<String, dynamic>.from(details);
  }

  static Future<PlacePrediction?> _resolvePredictionDistance(
    _PendingPlacePrediction pending, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      final details = await getPlaceDetails(pending.placeId);
      final detailLatitude = (details?['latitude'] as num?)?.toDouble();
      final detailLongitude = (details?['longitude'] as num?)?.toDouble();
      if (detailLatitude == null || detailLongitude == null) return null;
      final distance = proximityMeters(
        latitude,
        longitude,
        detailLatitude,
        detailLongitude,
      ).round();
      if (!isWithinSearchRadius(distance)) return null;
      return pending.toPrediction(distance);
    } catch (_) {
      return null;
    }
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

class _PendingPlacePrediction {
  const _PendingPlacePrediction({
    required this.placeId,
    required this.title,
    required this.subtitle,
  });

  final String placeId;
  final String title;
  final String? subtitle;

  PlacePrediction toPrediction(int distanceMeters) => PlacePrediction(
    placeId: placeId,
    title: title,
    subtitle: subtitle,
    distanceMeters: distanceMeters,
  );
}

class _CachedPlaceDetails {
  const _CachedPlaceDetails({required this.details, required this.createdAt});

  final Map<String, dynamic> details;
  final DateTime createdAt;
}
