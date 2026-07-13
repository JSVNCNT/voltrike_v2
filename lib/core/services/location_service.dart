import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'geolocation_service.dart';

/// High-level location service.
///
/// Uses GeolocationService internally.
///
/// This service should be used throughout the app instead of
/// calling Geolocator directly.
class LocationService {
  LocationService._();

  static final LocationService instance =
      LocationService._();

  StreamSubscription<Position>? _subscription;

  final StreamController<Position>
      _locationController =
      StreamController<Position>.broadcast();

  /// ==========================================================================
  /// Current Location
  /// ==========================================================================

  Future<Position> getCurrentLocation() {
    return GeolocationService.getCurrentLocation();
  }

  /// ==========================================================================
  /// Current Position Stream
  /// ==========================================================================

  Stream<Position> get locationStream =>
      _locationController.stream;

  /// ==========================================================================
  /// Start Tracking
  /// ==========================================================================

  Future<void> startTracking() async {
    await stopTracking();

    _subscription = GeolocationService
        .getPositionStream()
        .listen(
      _locationController.add,
    );
  }

  /// ==========================================================================
  /// Stop Tracking
  /// ==========================================================================

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// ==========================================================================
  /// Permission
  /// ==========================================================================

  Future<void> ensurePermission() {
    return GeolocationService.ensurePermission();
  }

  Future<bool> hasPermission() {
    return GeolocationService.hasPermission();
  }

  /// ==========================================================================
  /// Device Settings
  /// ==========================================================================

  Future<bool> openLocationSettings() {
    return GeolocationService
        .openLocationSettings();
  }

  Future<bool> openAppSettings() {
    return GeolocationService.openAppSettings();
  }

  /// ==========================================================================
  /// Dispose
  /// ==========================================================================

  Future<void> dispose() async {
    await stopTracking();
    await _locationController.close();
  }
}