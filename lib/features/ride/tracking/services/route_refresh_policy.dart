import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Throttles live route refreshes while still reacting to meaningful movement,
/// destination changes, stale ETAs, and previous request failures.
class RouteRefreshPolicy {
  RouteRefreshPolicy({
    this.movementThresholdMeters = 40,
    this.maximumAge = const Duration(seconds: 30),
    this.failureRetryDelay = const Duration(seconds: 10),
  });

  final double movementThresholdMeters;
  final Duration maximumAge;
  final Duration failureRetryDelay;

  LatLng? _lastOrigin;
  LatLng? _lastDestination;
  DateTime? _lastSuccessAt;
  DateTime? _lastAttemptAt;
  bool _loading = false;

  bool shouldRefresh({
    required LatLng origin,
    required LatLng destination,
    required bool hasRoute,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    if (_loading) return false;
    if (_lastAttemptAt != null &&
        _lastSuccessAt != _lastAttemptAt &&
        currentTime.difference(_lastAttemptAt!) < failureRetryDelay) {
      return false;
    }
    if (!hasRoute || _lastOrigin == null || _lastDestination == null) {
      return true;
    }
    if (_distanceMeters(_lastDestination!, destination) > 2) return true;
    if (_distanceMeters(_lastOrigin!, origin) >= movementThresholdMeters) {
      return true;
    }
    return _lastSuccessAt == null ||
        currentTime.difference(_lastSuccessAt!) >= maximumAge;
  }

  void begin([DateTime? now]) {
    _loading = true;
    _lastAttemptAt = now ?? DateTime.now();
  }

  void succeed({
    required LatLng origin,
    required LatLng destination,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    _loading = false;
    _lastOrigin = origin;
    _lastDestination = destination;
    _lastAttemptAt = currentTime;
    _lastSuccessAt = currentTime;
  }

  void fail() {
    _loading = false;
  }

  void reset() {
    _loading = false;
    _lastOrigin = null;
    _lastDestination = null;
    _lastAttemptAt = null;
    _lastSuccessAt = null;
  }

  double _distanceMeters(LatLng from, LatLng to) {
    const radius = 6371000.0;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLat = (to.latitude - from.latitude) * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
