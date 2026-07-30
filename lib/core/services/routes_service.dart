import 'dart:collection';
import 'dart:convert';

import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:http/http.dart' as http;

import '../../data/models/route_info.dart';
import '../../data/models/route_policy_advisory.dart';
import '../config/api_keys.dart';
import 'route_restriction_service.dart';

class RoutesService {
  RoutesService._();

  static const Duration _timeout = Duration(seconds: 12);
  static const Duration _cacheTtl = Duration(seconds: 45);
  static const int _maximumCacheEntries = 24;
  static final LinkedHashMap<String, _CachedRoute> _cache =
      LinkedHashMap<String, _CachedRoute>();
  static final Map<String, Future<RouteInfo?>> _inFlight =
      <String, Future<RouteInfo?>>{};

  static const String _baseUrl =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Goog-Api-Key': ApiKeys.googleMapsApiKey,
    'X-Goog-FieldMask':
        'routes.routeToken,routes.distanceMeters,routes.duration,'
        'routes.polyline.encodedPolyline,'
        'routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration,'
        'routes.legs.steps.startLocation,routes.legs.steps.endLocation,'
        'routes.legs.steps.polyline.encodedPolyline,'
        'routes.legs.steps.navigationInstruction,'
        'routes.travelAdvisory.routeRestrictionsPartiallyIgnored',
  };

  /// Requests Google alternatives, asks the provider to avoid highways, then
  /// selects a route that does not enter an enforced restricted polygon.
  static Future<RouteInfo?> computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final key = _routeKey(origin, destination);
    final now = DateTime.now();
    final cached = _cache.remove(key);
    if (cached != null && now.difference(cached.createdAt) <= _cacheTtl) {
      _cache[key] = cached;
      return cached.route;
    }

    final existing = _inFlight[key];
    if (existing != null) return existing;
    final request = _computeRoute(origin: origin, destination: destination);
    _inFlight[key] = request;
    try {
      final route = await request;
      if (route != null) {
        _cache[key] = _CachedRoute(route: route, createdAt: DateTime.now());
        while (_cache.length > _maximumCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return route;
    } finally {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    }
  }

  static Future<RouteInfo?> _computeRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: _headers,
            body: jsonEncode(
              buildRequest(origin: origin, destination: destination),
            ),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawRoutes = decoded['routes'] as List?;
      if (rawRoutes == null || rawRoutes.isEmpty) return null;

      final restrictions = RouteRestrictionService.instance;
      restrictions.clearLastConflict();
      final avoidedRestrictionNames = <String>{};
      RouteInfo? highwayAdvisoryFallback;
      for (final raw in rawRoutes) {
        final route = parseGoogleRoute(raw as Map<String, dynamic>);
        final conflict = await restrictions.encodedRouteConflict(
          route.encodedPolyline,
        );
        if (conflict == null) {
          final candidate = route.copyWith(
            avoidedRestrictionNames: List<String>.unmodifiable(
              avoidedRestrictionNames,
            ),
            routePolicy: route.routePolicy.copyWith(
              avoidedRestrictionNames: List<String>.unmodifiable(
                avoidedRestrictionNames,
              ),
            ),
          );
          if (!route.routePolicy.restrictionsPartiallyIgnored) {
            return candidate;
          }
          highwayAdvisoryFallback ??= candidate;
          continue;
        }
        avoidedRestrictionNames.add(conflict.name);
        restrictions.markConflict(conflict);
      }
      // A polygon-safe flagged route remains a pilot fallback only after all
      // alternatives have been checked for an unflagged option.
      return highwayAdvisoryFallback;
    } on FormatException {
      return null;
    } on http.ClientException {
      return null;
    } catch (_) {
      // Restriction policy is fail-closed. If Firestore cannot provide the
      // active polygons (or any unexpected validation step fails), callers
      // receive no route instead of an unchecked provider route.
      return null;
    }
  }

  static Map<String, dynamic> buildRequest({
    required LatLng origin,
    required LatLng destination,
  }) {
    return {
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
      'computeAlternativeRoutes': true,
      'routeModifiers': {'avoidHighways': true},
    };
  }

  static RouteInfo parseGoogleRoute(Map<String, dynamic> route) {
    final distanceMeters = (route['distanceMeters'] as num?)?.round() ?? 0;
    final durationSeconds = _durationSeconds(
      route['duration'] as String? ?? '0s',
    );
    final encodedPolyline =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String? ??
        '';
    final steps = <RouteStep>[];
    final travelAdvisory =
        route['travelAdvisory'] as Map<String, dynamic>? ?? const {};
    for (final leg in route['legs'] as List? ?? const []) {
      for (final rawStep
          in (leg as Map<String, dynamic>)['steps'] as List? ?? const []) {
        final step = rawStep as Map<String, dynamic>;
        final navigation =
            step['navigationInstruction'] as Map<String, dynamic>? ?? const {};
        final start =
            (step['startLocation'] as Map<String, dynamic>?)?['latLng']
                as Map<String, dynamic>? ??
            const {};
        final end =
            (step['endLocation'] as Map<String, dynamic>?)?['latLng']
                as Map<String, dynamic>? ??
            const {};
        final polyline = step['polyline'] as Map<String, dynamic>? ?? const {};
        steps.add(
          RouteStep(
            instruction: navigation['instructions'] as String? ?? '',
            maneuver: navigation['maneuver'] as String? ?? '',
            distanceMeters: (step['distanceMeters'] as num?)?.round() ?? 0,
            durationSeconds: _durationSeconds(
              step['staticDuration'] as String? ?? '0s',
            ),
            startLocation: LatLng(
              (start['latitude'] as num?)?.toDouble() ?? 0,
              (start['longitude'] as num?)?.toDouble() ?? 0,
            ),
            endLocation: LatLng(
              (end['latitude'] as num?)?.toDouble() ?? 0,
              (end['longitude'] as num?)?.toDouble() ?? 0,
            ),
            encodedPolyline: polyline['encodedPolyline'] as String? ?? '',
          ),
        );
      }
    }
    return RouteInfo(
      distanceMeters: distanceMeters,
      distanceKm: distanceMeters / 1000,
      durationMinutes: (durationSeconds / 60).ceil(),
      encodedPolyline: encodedPolyline,
      routeToken: route['routeToken'] as String?,
      routePolicy: RoutePolicyAdvisory(
        restrictionsPartiallyIgnored:
            travelAdvisory['routeRestrictionsPartiallyIgnored'] == true,
      ),
      steps: steps,
    );
  }

  static int _durationSeconds(String value) =>
      (double.tryParse(value.replaceAll('s', '')) ?? 0).round();

  static String _routeKey(LatLng origin, LatLng destination) {
    String coordinate(LatLng point) =>
        '${point.latitude.toStringAsFixed(5)},'
        '${point.longitude.toStringAsFixed(5)}';
    return '${coordinate(origin)}>${coordinate(destination)}';
  }
}

class _CachedRoute {
  const _CachedRoute({required this.route, required this.createdAt});

  final RouteInfo route;
  final DateTime createdAt;
}
