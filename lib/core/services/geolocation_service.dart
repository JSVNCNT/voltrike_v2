import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// Service for accessing the device's GPS location.
///
/// NOTE:
/// This service is ONLY responsible for device location.
///
/// Philippine Region / Province / City / Barangay data
/// is handled by PSGCService.
class GeolocationService {
  const GeolocationService._();

  /// Returns true if the device location service is enabled.
  static Future<bool> isLocationEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Returns the current permission status.
  static Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  /// Requests location permission from the user.
  static Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  /// Checks if the application has location permission.
  static Future<bool> hasPermission() async {
    final permission = await checkPermission();

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Ensures the application can access location.
  ///
  /// Throws an Exception if location services are disabled
  /// or permission is denied.
  static Future<void> ensurePermission() async {
    final enabled = await isLocationEnabled();

    if (!enabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission permanently denied. '
        'Please enable it in device settings.',
      );
    }
  }

  /// Returns the user's current GPS location.
  static Future<Position> getCurrentLocation() async {
    await ensurePermission();

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Continuously listens for location updates.
  static Stream<Position> getPositionStream() {
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'VolTrike ride location active',
              notificationText: 'Sharing driver location for the active ride.',
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          );
    return Geolocator.getPositionStream(
      locationSettings: settings,
    );
  }

  /// Opens the device location settings.
  static Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  /// Opens the application permission settings.
  static Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }
}
