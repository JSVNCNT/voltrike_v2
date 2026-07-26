import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
class DriverLocationState {
  const DriverLocationState({
    this.location,
    this.isTracking = false,
    this.isStarting = false,
    this.errorMessage,
    this.lastPublishedAt,
  });

  final LatLng? location;
  final bool isTracking;
  final bool isStarting;
  final String? errorMessage;
  final DateTime? lastPublishedAt;

  DriverLocationState copyWith({
    LatLng? location,
    bool clearLocation = false,
    bool? isTracking,
    bool? isStarting,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastPublishedAt,
  }) {
    return DriverLocationState(
      location: clearLocation ? null : location ?? this.location,
      isTracking: isTracking ?? this.isTracking,
      isStarting: isStarting ?? this.isStarting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
    );
  }
}

class DriverLocationController extends StateNotifier<DriverLocationState> {
  DriverLocationController({required AuthRepository authRepository})
    : _authRepository = authRepository,
      super(const DriverLocationState());

  final AuthRepository _authRepository;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  StreamSubscription<Position>? _subscription;
  Timer? _heartbeat;
  AppLifecycleListener? _lifecycleListener;
  DateTime? _lastDatabaseWrite;
  Position? _lastPosition;
  DatabaseReference? _locationRef;
  DatabaseReference? _presenceRef;

  bool get isTracking => _subscription != null;

  //==========================================================================
  // Start Tracking
  //==========================================================================

  Future<void> startTracking() async {
    if (_subscription != null) {
      return;
    }

    state = state.copyWith(isStarting: true, clearError: true);

    try {
      final driver = _authRepository.currentUser;

      if (driver == null) {
        throw Exception('No authenticated driver.');
      }

      _locationRef = _database.ref('driver_locations/${driver.uid}');
      _presenceRef = _database.ref('driver_presence/${driver.uid}');

      await LocationService.instance.ensurePermission();

      await LocationService.instance.startTracking();

      await _locationRef!.onDisconnect().remove();
      await _presenceRef!.onDisconnect().set({
        'online': false,
        'updatedAt': ServerValue.timestamp,
      });
      await _presenceRef!.set({
        'online': true,
        'updatedAt': ServerValue.timestamp,
      });

      NavigationService.instance.bindLiveLocation(
        LocationService.instance.locationStream,
      );

      _subscription = LocationService.instance.locationStream.listen((
        position,
      ) async {
        _lastPosition = position;
        state = state.copyWith(
          location: LatLng(position.latitude, position.longitude),
          isTracking: true,
          isStarting: false,
          clearError: true,
        );
        await _writeLocation(_locationRef!, position);
      }, onError: (Object error, StackTrace _) {
        state = state.copyWith(
          isStarting: false,
          errorMessage: _messageFor(error),
        );
      });

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        final position = _lastPosition;
        final locationRef = _locationRef;
        if (position != null && locationRef != null) {
          unawaited(_writeLocation(locationRef, position));
        }
      });
      _lifecycleListener ??= AppLifecycleListener(onResume: _refreshOnResume);

      await _refreshOnResume();
      state = state.copyWith(
        isTracking: true,
        isStarting: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        clearLocation: true,
        isTracking: false,
        isStarting: false,
        errorMessage: _messageFor(e),
      );
      rethrow;
    }
  }

  //==========================================================================
  // Stop Tracking
  //==========================================================================

  Future<void> stopTracking() async {
    state = state.copyWith(isStarting: true, clearError: true);

    try {
      _heartbeat?.cancel();
      _heartbeat = null;
      await _subscription?.cancel();
      _subscription = null;

      await LocationService.instance.stopTracking();

      final driver = _authRepository.currentUser;
      if (driver != null) {
        await _database.ref('driver_locations/${driver.uid}').remove();
        await _database.ref('driver_presence/${driver.uid}').set({
          'online': false,
          'updatedAt': ServerValue.timestamp,
        });
        await _database
            .ref('driver_locations/${driver.uid}')
            .onDisconnect()
            .cancel();
        await _database
            .ref('driver_presence/${driver.uid}')
            .onDisconnect()
            .cancel();
      }

      _lastDatabaseWrite = null;
      _lastPosition = null;
      _locationRef = null;
      _presenceRef = null;
      state = state.copyWith(
        isTracking: false,
        isStarting: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isTracking: false,
        isStarting: false,
        errorMessage: _messageFor(e),
      );
      rethrow;
    }
  }

  Future<void> _refreshOnResume() async {
    final locationRef = _locationRef;
    if (locationRef == null || _subscription == null) return;
    try {
      final position = await LocationService.instance.currentPosition();
      _lastPosition = position;
      state = state.copyWith(
        location: LatLng(position.latitude, position.longitude),
        clearError: true,
      );
      await _writeLocation(locationRef, position, force: true);
      await _presenceRef?.set({
        'online': true,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (error) {
      state = state.copyWith(errorMessage: _messageFor(error));
    }
  }

  Future<void> _writeLocation(
    DatabaseReference locationRef,
    Position position, {
    bool force = false,
  }) async {
    if (position.accuracy < 0 || position.accuracy > 100) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastDatabaseWrite != null &&
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
    state = state.copyWith(lastPublishedAt: now);
  }

  String _messageFor(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permanently denied')) {
      return 'Location permission is disabled in app settings.';
    }
    if (text.contains('permission denied')) {
      return 'Location permission is required while driving.';
    }
    if (text.contains('services are disabled')) {
      return 'Turn on device location services.';
    }
    return 'Driver location is temporarily unavailable.';
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  @override
  void dispose() {
    _heartbeat?.cancel();
    _subscription?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    LocationService.instance.stopTracking();

    super.dispose();
  }
}
