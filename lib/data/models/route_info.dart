import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import 'route_policy_advisory.dart';

class RouteInfo {
  final int distanceMeters;
  final double distanceKm;
  final int durationMinutes;
  final String encodedPolyline;
  final String? routeToken;

  /// Restrictions encountered on rejected alternatives before this safe route.
  final List<String> avoidedRestrictionNames;
  final RoutePolicyAdvisory routePolicy;

  /// NEW
  final List<RouteStep> steps;

  const RouteInfo({
    required this.distanceMeters,
    required this.distanceKm,
    required this.durationMinutes,
    required this.encodedPolyline,
    this.routeToken,
    this.avoidedRestrictionNames = const [],
    this.routePolicy = const RoutePolicyAdvisory(),
    this.steps = const [],
  });

  RouteInfo copyWith({
    List<String>? avoidedRestrictionNames,
    RoutePolicyAdvisory? routePolicy,
  }) {
    return RouteInfo(
      distanceMeters: distanceMeters,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      encodedPolyline: encodedPolyline,
      routeToken: routeToken,
      avoidedRestrictionNames:
          avoidedRestrictionNames ?? this.avoidedRestrictionNames,
      routePolicy: routePolicy ?? this.routePolicy,
      steps: steps,
    );
  }
}

class RouteStep {
  final String instruction;
  final String maneuver;

  final int distanceMeters;
  final int durationSeconds;

  final LatLng startLocation;
  final LatLng endLocation;

  final String encodedPolyline;

  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startLocation,
    required this.endLocation,
    required this.encodedPolyline,
  });
}
