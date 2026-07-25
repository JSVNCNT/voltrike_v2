import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteInfo {
  final int distanceMeters;
  final double distanceKm;
  final int durationMinutes;
  final String encodedPolyline;

  /// NEW
  final List<RouteStep> steps;

  const RouteInfo({
    required this.distanceMeters,
    required this.distanceKm,
    required this.durationMinutes,
    required this.encodedPolyline,
    this.steps = const [],
  });
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