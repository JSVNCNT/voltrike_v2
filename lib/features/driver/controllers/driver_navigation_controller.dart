import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/navigation_service.dart';
import '../../../core/services/route_restriction_service.dart';
import '../../ride/tracking/services/route_refresh_policy.dart';

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
    this.restrictionWarning,
    this.instruction,
    this.maneuver,
    this.nextInstruction,
    this.loading = false,
  });

  final List<LatLng> routePoints;
  final String? eta;
  final String? distance;
  final String? duration;
  final String? restrictionWarning;
  final String? instruction;
  final String? maneuver;
  final String? nextInstruction;
  final bool loading;

  DriverNavigationState copyWith({
    List<LatLng>? routePoints,
    String? eta,
    String? distance,
    String? duration,
    String? restrictionWarning,
    String? instruction,
    String? maneuver,
    String? nextInstruction,
    bool? loading,
  }) {
    return DriverNavigationState(
      routePoints: routePoints ?? this.routePoints,
      eta: eta ?? this.eta,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      restrictionWarning: restrictionWarning ?? this.restrictionWarning,
      instruction: instruction ?? this.instruction,
      maneuver: maneuver ?? this.maneuver,
      nextInstruction: nextInstruction ?? this.nextInstruction,
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
  final RouteRefreshPolicy _refreshPolicy = RouteRefreshPolicy();

  //==========================================================================
  // Load Route
  //==========================================================================

  Future<void> loadRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!_refreshPolicy.shouldRefresh(
      origin: origin,
      destination: destination,
      hasRoute: state.routePoints.isNotEmpty,
    )) {
      return;
    }
    _refreshPolicy.begin();
    state = state.copyWith(loading: true);

    try {
      RouteRestrictionService.instance.clearLastConflict();
      final routeInfo = await _navigation.computeRouteInfo(
        origin: origin,
        destination: destination,
      );

      if (routeInfo == null) {
        _refreshPolicy.fail();
        final conflict = RouteRestrictionService.instance.lastConflict;
        state = state.copyWith(
          restrictionWarning: conflict == null
              ? 'No route is currently available.'
              : 'Route blocked: ${conflict.name}. Use the approved alternate route.',
          loading: false,
        );
        return;
      }

      final encodedPolyline = routeInfo.encodedPolyline;

      final points =
          _navigation.decodePolyline(encodedPolyline);

      state = DriverNavigationState(
        routePoints: points,
        eta: '${routeInfo.durationMinutes} min',
        duration: '${routeInfo.durationMinutes} min',
        distance: '${routeInfo.distanceKm.toStringAsFixed(1)} km',
        instruction: routeInfo.steps.isEmpty ? null : routeInfo.steps.first.instruction,
        maneuver: routeInfo.steps.isEmpty ? null : routeInfo.steps.first.maneuver,
        nextInstruction: routeInfo.steps.length < 2 ? null : routeInfo.steps[1].instruction,
        loading: false,
      );
      _refreshPolicy.succeed(origin: origin, destination: destination);
    } catch (_) {
      _refreshPolicy.fail();
      state = state.copyWith(
        loading: false,
        restrictionWarning: state.restrictionWarning ??
            'Live route is temporarily unavailable.',
      );
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

  /// Called from live GPS updates to warn a driver who enters a developer-
  /// restricted polygon even if a previously rendered route is still visible.
  Future<void> checkCurrentPosition(LatLng position) async {
    final conflict = await RouteRestrictionService.instance.pointConflict(position);
    state = state.copyWith(
      restrictionWarning: conflict == null
          ? ''
          : 'Restricted area entered: ${conflict.name}. Leave via a safe route.',
    );
  }

  //==========================================================================
  // Clear Route
  //==========================================================================

  void clearRoute() {
    _refreshPolicy.reset();
    state = DriverNavigationState.empty;
  }
}
