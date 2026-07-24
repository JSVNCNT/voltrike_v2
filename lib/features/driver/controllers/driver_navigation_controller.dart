import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/navigation_service.dart';

/// ===========================================================================
/// Driver Navigation State
///
/// Holds the current navigation information displayed on the map.
/// ===========================================================================
class DriverNavigationState {
  const DriverNavigationState({
    this.routePoints = const [],
    this.eta,
    this.distance,
    this.duration,
    this.loading = false,
  });

  final List<LatLng> routePoints;
  final String? eta;
  final String? distance;
  final String? duration;
  final bool loading;

  DriverNavigationState copyWith({
    List<LatLng>? routePoints,
    String? eta,
    String? distance,
    String? duration,
    bool? loading,
  }) {
    return DriverNavigationState(
      routePoints: routePoints ?? this.routePoints,
      eta: eta ?? this.eta,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      loading: loading ?? this.loading,
    );
  }

  static const empty = DriverNavigationState();
}

/// ===========================================================================
/// Driver Navigation Controller
///
/// Responsibilities:
/// • Compute pickup route
/// • Compute destination route
/// • Decode polyline
/// • Expose ETA
/// • Expose distance
/// • Expose duration
/// • Clear navigation
/// ===========================================================================
class DriverNavigationController
    extends StateNotifier<DriverNavigationState> {
  DriverNavigationController({
    NavigationService? navigationService,
  })  : _navigation =
            navigationService ?? NavigationService.instance,
        super(DriverNavigationState.empty);

  final NavigationService _navigation;

  //==========================================================================
  // Load Route
  //==========================================================================

  Future<void> loadRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    state = state.copyWith(loading: true);

    try {
      final route = await _navigation.computeTrafficRoute(
        origin: origin,
        destination: destination,
      );

      if (route == null) {
        clearRoute();
        return;
      }

      final encodedPolyline =
          _navigation.encodedPolyline(route);

      final points =
          _navigation.decodePolyline(encodedPolyline);

      state = DriverNavigationState(
        routePoints: points,
        eta: _navigation.duration(route),
        duration: _navigation.duration(route),
        distance:
            '${_navigation.distanceKm(route).toStringAsFixed(1)} km',
        loading: false,
      );
    } catch (_) {
      clearRoute();
    }
  }

  //==========================================================================
  // Pickup Route
  //==========================================================================

  Future<void> navigateToPickup({
    required LatLng driverLocation,
    required LatLng pickup,
  }) {
    return loadRoute(
      origin: driverLocation,
      destination: pickup,
    );
  }

  //==========================================================================
  // Destination Route
  //==========================================================================

  Future<void> navigateToDestination({
    required LatLng driverLocation,
    required LatLng destination,
  }) {
    return loadRoute(
      origin: driverLocation,
      destination: destination,
    );
  }

  //==========================================================================
  // Clear Route
  //==========================================================================

  void clearRoute() {
    state = DriverNavigationState.empty;
  }
}