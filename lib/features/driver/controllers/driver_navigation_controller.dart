import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../../core/services/navigation_service.dart';
import '../../../core/services/route_restriction_service.dart';
import '../../../data/models/route_info.dart';
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
    this.isTurnByTurnActive = false,
    this.isRerouting = false,
    this.navigationError,
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
  final bool isTurnByTurnActive;
  final bool isRerouting;
  final String? navigationError;

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
    bool? isTurnByTurnActive,
    bool? isRerouting,
    String? navigationError,
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
      isTurnByTurnActive: isTurnByTurnActive ?? this.isTurnByTurnActive,
      isRerouting: isRerouting ?? this.isRerouting,
      navigationError: navigationError ?? this.navigationError,
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
class DriverNavigationController extends StateNotifier<DriverNavigationState> {
  DriverNavigationController({NavigationService? navigationService})
    : _navigation = navigationService ?? NavigationService.instance,
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

      final points = _navigation.decodePolyline(encodedPolyline);

      state = DriverNavigationState(
        routePoints: points,
        eta: '${routeInfo.durationMinutes} min',
        duration: '${routeInfo.durationMinutes} min',
        distance: '${routeInfo.distanceKm.toStringAsFixed(1)} km',
        instruction: routeInfo.steps.isEmpty
            ? null
            : routeInfo.steps.first.instruction,
        maneuver: routeInfo.steps.isEmpty
            ? null
            : routeInfo.steps.first.maneuver,
        nextInstruction: routeInfo.steps.length < 2
            ? null
            : routeInfo.steps[1].instruction,
        restrictionWarning: routeInfo.routePolicy.driverMessage.isEmpty
            ? null
            : routeInfo.routePolicy.driverMessage,
        loading: false,
      );
      _refreshPolicy.succeed(origin: origin, destination: destination);
    } catch (_) {
      _refreshPolicy.fail();
      state = state.copyWith(
        loading: false,
        restrictionWarning:
            state.restrictionWarning ??
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
    return loadRoute(origin: driverLocation, destination: pickup);
  }

  //==========================================================================
  // Destination Route
  //==========================================================================

  Future<void> navigateToDestination({
    required LatLng driverLocation,
    required LatLng destination,
  }) {
    return loadRoute(origin: driverLocation, destination: destination);
  }

  /// Mirrors the policy-validated Routes API result used to seed native
  /// guidance with a route token.
  void applyValidatedRoute(RouteInfo routeInfo) {
    state = state.copyWith(
      routePoints: _navigation.decodePolyline(routeInfo.encodedPolyline),
      eta: '${routeInfo.durationMinutes} min',
      duration: '${routeInfo.durationMinutes} min',
      distance: '${routeInfo.distanceKm.toStringAsFixed(1)} km',
      restrictionWarning: routeInfo.routePolicy.driverMessage,
      loading: false,
    );
  }

  /// Called from live GPS updates to warn a driver who enters a developer-
  /// restricted polygon even if a previously rendered route is still visible.
  Future<void> checkCurrentPosition(LatLng position) async {
    final conflict = await RouteRestrictionService.instance.pointConflict(
      position,
    );
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

  /// Applies traffic-aware progress emitted by the native Navigation SDK.
  void updateSdkProgress({
    required double remainingTimeSeconds,
    required double remainingDistanceMeters,
  }) {
    final minutes = (remainingTimeSeconds / 60).ceil().clamp(1, 9999);
    final distance = remainingDistanceMeters >= 1000
        ? '${(remainingDistanceMeters / 1000).toStringAsFixed(1)} km'
        : '${remainingDistanceMeters.round()} m';
    state = state.copyWith(
      eta: '$minutes min',
      duration: '$minutes min',
      distance: distance,
      loading: false,
      isTurnByTurnActive: true,
      isRerouting: false,
      navigationError: '',
    );
  }

  void updateSdkInstructions({
    String? instruction,
    String? nextInstruction,
    String? maneuver,
  }) {
    state = state.copyWith(
      instruction: instruction,
      nextInstruction: nextInstruction,
      maneuver: maneuver,
      isTurnByTurnActive: true,
      navigationError: '',
    );
  }

  void markSdkStarting() {
    state = state.copyWith(
      loading: true,
      isTurnByTurnActive: false,
      isRerouting: false,
      navigationError: '',
    );
  }

  void markSdkReady() {
    state = state.copyWith(
      loading: false,
      isTurnByTurnActive: true,
      isRerouting: false,
      navigationError: '',
    );
  }

  void markSdkRerouting() {
    state = state.copyWith(
      isRerouting: true,
      instruction: 'Finding a safer route…',
    );
  }

  void markSdkArrival(String destinationLabel) {
    state = state.copyWith(
      eta: 'Arrived',
      distance: '0 m',
      duration: '0 min',
      instruction: 'Arrived at $destinationLabel',
      nextInstruction: '',
      loading: false,
      isRerouting: false,
    );
  }

  void setSdkError(String message) {
    state = state.copyWith(
      loading: false,
      isTurnByTurnActive: false,
      isRerouting: false,
      navigationError: message,
    );
  }
}
