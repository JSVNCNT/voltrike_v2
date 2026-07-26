import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../data/repositories/auth_repository.dart';

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
    required AuthRepository authRepository,
  })  : _authRepository = authRepository,
        super(const AsyncData(null));

  final AuthRepository _authRepository;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  StreamSubscription<Position>? _subscription;
  DateTime? _lastDatabaseWrite;

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

      final locationRef = _database.ref('driver_locations/${driver.uid}');
      final presenceRef = _database.ref('driver_presence/${driver.uid}');

      await presenceRef.set({
        'online': true,
        'updatedAt': ServerValue.timestamp,
      });

      await LocationService.instance
          .ensurePermission();

      await LocationService.instance
          .startTracking();

      NavigationService.instance.bindLiveLocation(
        LocationService.instance.locationStream,
      );

      _subscription = LocationService
          .instance
          .locationStream
          .listen(
        (position) async {
          final now = DateTime.now();
          if (_lastDatabaseWrite != null &&
              now.difference(_lastDatabaseWrite!) < const Duration(seconds: 10)) {
            return;
          }
          _lastDatabaseWrite = now;
          await locationRef.set({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'bearing': position.heading,
            'speed': position.speed,
            'accuracy': position.accuracy,
            'timestamp': ServerValue.timestamp,
            'online': true,
            'updatedAt': ServerValue.timestamp,
          });
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

      final driver = _authRepository.currentUser;
      if (driver != null) {
        await _database.ref('driver_locations/${driver.uid}').update({
          'online': false,
          'updatedAt': ServerValue.timestamp,
        });
        await _database.ref('driver_presence/${driver.uid}').set({
          'online': false,
          'updatedAt': ServerValue.timestamp,
        });
      }

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
