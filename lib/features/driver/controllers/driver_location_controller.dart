import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/driver_repository.dart';

/// ===========================================================================
/// Driver Location Controller
///
/// Handles:
/// • Driver GPS tracking
/// • Uploading live location to Firestore
/// • Starting / stopping tracking
///
/// Flow:
///
/// Driver Online
///      ↓
/// Start GPS
///      ↓
/// Listen Position Stream
///      ↓
/// Update Firestore
///      ↓
/// Driver Offline
///      ↓
/// Stop GPS
/// ===========================================================================
class DriverLocationController
    extends StateNotifier<AsyncValue<void>> {
  DriverLocationController({
    required DriverRepository driverRepository,
    required AuthRepository authRepository,
  })  : _driverRepository = driverRepository,
        _authRepository = authRepository,
        super(const AsyncData(null));

  final DriverRepository _driverRepository;
  final AuthRepository _authRepository;

  StreamSubscription<Position>? _subscription;

  bool get isTracking =>
      _subscription != null;

  //==========================================================================
  // Start Tracking
  //==========================================================================

  Future<void> startTracking() async {
    if (_subscription != null) {
      return;
    }

    state = const AsyncLoading();

    try {
      final driver =
          _authRepository.currentUser;

      if (driver == null) {
        throw Exception(
          'No authenticated driver.',
        );
      }

      await LocationService.instance
          .ensurePermission();

      await LocationService.instance
          .startTracking();

      _subscription = LocationService
          .instance
          .locationStream
          .listen(
        (position) async {
          await _driverRepository
              .updateLocation(
            uid: driver.uid,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        },
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  //==========================================================================
  // Stop Tracking
  //==========================================================================

  Future<void> stopTracking() async {
    state = const AsyncLoading();

    try {
      await _subscription?.cancel();
      _subscription = null;

      await LocationService.instance
          .stopTracking();

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(
        e,
        stackTrace,
      );

      rethrow;
    }
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  @override
  void dispose() {
    _subscription?.cancel();

    LocationService.instance
        .stopTracking();

    super.dispose();
  }
}