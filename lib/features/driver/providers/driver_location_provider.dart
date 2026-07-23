import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/navigation_service.dart';

/// ===========================================================================
/// Driver Location Provider
///
/// Tracks the driver's live GPS location.
///
/// Uses:
/// • NavigationService
///
/// Shared by:
/// • DriverHomeScreen
/// • DriverMapView
/// • DriverBottomSheet
/// • DriverBookingController
/// ===========================================================================
class DriverLocationNotifier
    extends StateNotifier<LatLng?> {
  DriverLocationNotifier()
      : super(null);

  final NavigationService _navigation =
      NavigationService.instance;

  StreamSubscription? _subscription;

  //==========================================================================
  // Start Tracking
  //==========================================================================

  Future<void> startTracking() async {
    await _navigation.startNavigation();

    await _subscription?.cancel();

    _subscription =
        _navigation.locationStream.listen(
      (position) {
        state = LatLng(
          position.latitude,
          position.longitude,
        );
      },
    );
  }

  //==========================================================================
  // Stop Tracking
  //==========================================================================

  Future<void> stopTracking() async {
    await _subscription?.cancel();

    _subscription = null;
  }

  //==========================================================================
  // Current Location
  //==========================================================================

  Future<void> refreshLocation() async {
    final position =
        await _navigation.currentLocation();

    state = LatLng(
      position.latitude,
      position.longitude,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// ===========================================================================
/// Driver Location Provider
/// ===========================================================================

final driverLocationProvider =
    StateNotifierProvider<
        DriverLocationNotifier,
        LatLng?>(
  (ref) => DriverLocationNotifier(),
);