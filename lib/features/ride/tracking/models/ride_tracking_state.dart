import 'package:google_maps_flutter/google_maps_flutter.dart';

class RideTrackingState {
  const RideTrackingState({
    this.markers = const {},
    this.polylines = const {},
    this.cameraPosition,
    this.routePoints = const [],
    this.distanceText,
    this.durationText,
    this.isFollowingDriver = true,
    this.isLoadingRoute = false,
  });

  final Set<Marker> markers;

  final Set<Polyline> polylines;

  final CameraPosition? cameraPosition;

  final List<LatLng> routePoints;

  final String? distanceText;

  final String? durationText;

  final bool isFollowingDriver;

  final bool isLoadingRoute;

  RideTrackingState copyWith({
    Set<Marker>? markers,
    Set<Polyline>? polylines,
    CameraPosition? cameraPosition,
    List<LatLng>? routePoints,
    String? distanceText,
    String? durationText,
    bool? isFollowingDriver,
    bool? isLoadingRoute,
  }) {
    return RideTrackingState(
      markers: markers ?? this.markers,
      polylines: polylines ?? this.polylines,
      cameraPosition: cameraPosition ?? this.cameraPosition,
      routePoints: routePoints ?? this.routePoints,
      distanceText: distanceText ?? this.distanceText,
      durationText: durationText ?? this.durationText,
      isFollowingDriver:
          isFollowingDriver ?? this.isFollowingDriver,
      isLoadingRoute:
          isLoadingRoute ?? this.isLoadingRoute,
    );
  }
}