import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/services/voltrike_api.dart';
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
    this.lastPublishedObservedAt,
    this.accuracyMeters,
    this.observedAt,
  });

  final LatLng? location;
  final bool isTracking;
  final bool isStarting;
  final String? errorMessage;
  final DateTime? lastPublishedAt;
  final DateTime? lastPublishedObservedAt;
  final double? accuracyMeters;
  final DateTime? observedAt;

  DriverLocationState copyWith({
    LatLng? location,
    bool clearLocation = false,
    bool? isTracking,
    bool? isStarting,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastPublishedAt,
    DateTime? lastPublishedObservedAt,
    double? accuracyMeters,
    DateTime? observedAt,
  }) {
    return DriverLocationState(
      location: clearLocation ? null : location ?? this.location,
      isTracking: isTracking ?? this.isTracking,
      isStarting: isStarting ?? this.isStarting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
      lastPublishedObservedAt: clearLocation
          ? null
          : lastPublishedObservedAt ?? this.lastPublishedObservedAt,
      accuracyMeters: clearLocation
          ? null
          : accuracyMeters ?? this.accuracyMeters,
      observedAt: clearLocation ? null : observedAt ?? this.observedAt,
    );
  }
}

class DriverLocationController extends StateNotifier<DriverLocationState> {
  DriverLocationController({
    required AuthRepository authRepository,
    VoltrikeApi? api,
  }) : _authRepository = authRepository,
       _api = api ?? VoltrikeApi.instance,
       super(const DriverLocationState());

  final AuthRepository _authRepository;
  final VoltrikeApi _api;
  final Uuid _uuid = const Uuid();

  StreamSubscription<Position>? _subscription;
  Timer? _heartbeat;
  AppLifecycleListener? _lifecycleListener;
  DateTime? _lastDatabaseWrite;
  Position? _lastPosition;
  String? _sessionId;
  int _leaseGeneration = 0;
  int _sampleSequence = 0;
  bool _disposed = false;

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

      _sessionId = _uuid.v4();
      _leaseGeneration = 1;
      _sampleSequence = 0;
      await _api.createDriverSession({
        'sessionId': _sessionId,
        'deviceId': 'flutter-${_uuid.v4()}',
        'platform': defaultTargetPlatform.name,
        'appVersion': const String.fromEnvironment(
          'FLUTTER_APP_VERSION',
          defaultValue: 'dev',
        ),
        'takeover': true,
      });

      await LocationService.instance.ensurePermission();

      await LocationService.instance.startTracking();

      NavigationService.instance.bindLiveLocation(
        LocationService.instance.locationStream,
      );

      _subscription = LocationService.instance.locationStream.listen(
        (position) {
          if (_disposed) return;
          _lastPosition = position;
          state = state.copyWith(
            location: LatLng(position.latitude, position.longitude),
            accuracyMeters: position.accuracy,
            observedAt: position.timestamp,
            isTracking: true,
            isStarting: false,
            clearError: true,
          );
          unawaited(_publishLocation(position));
        },
        onError: (Object error, StackTrace _) {
          if (_disposed) return;
          state = state.copyWith(
            isStarting: false,
            errorMessage: _messageFor(error),
          );
        },
      );

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        final position = _lastPosition;
        if (!_disposed && position != null && _sessionId != null) {
          unawaited(_publishLocation(position));
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

      final position = _lastPosition;
      if (position != null && _sessionId != null) {
        await _writeLocation(position, force: true, online: false);
      }

      _lastDatabaseWrite = null;
      _lastPosition = null;
      _sessionId = null;
      _leaseGeneration = 0;
      _sampleSequence = 0;
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
    if (_sessionId == null || _subscription == null) return;
    try {
      final position = await LocationService.instance.currentPosition();
      _lastPosition = position;
      state = state.copyWith(
        location: LatLng(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
        observedAt: position.timestamp,
        clearError: true,
      );
      await _writeLocation(position, force: true);
    } catch (error) {
      state = state.copyWith(errorMessage: _messageFor(error));
    }
  }

  Future<void> _writeLocation(
    Position position, {
    bool force = false,
    bool online = true,
  }) async {
    if (_disposed) return;
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
    final sessionId = _sessionId;
    if (sessionId == null) return;
    _sampleSequence += 1;
    await _api.updateLocation(sessionId, {
      'leaseGeneration': _leaseGeneration,
      'sampleSequence': _sampleSequence,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'observedAt': position.timestamp.toUtc().toIso8601String(),
      'online': online,
      'available': online,
    });
    if (_disposed) return;
    state = state.copyWith(
      lastPublishedAt: now,
      lastPublishedObservedAt: position.timestamp,
    );
  }

  Future<void> _publishLocation(Position position) async {
    try {
      await _writeLocation(position);
    } catch (error) {
      // Location streams and periodic timers do not await their callbacks.
      // Contain transient API failures here so they cannot become uncaught
      // framework errors while the driver remains online.
      _lastDatabaseWrite = null;
      if (_disposed) return;
      state = state.copyWith(errorMessage: _messageFor(error));
    }
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
    _disposed = true;
    _heartbeat?.cancel();
    _subscription?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    LocationService.instance.stopTracking();

    super.dispose();
  }
}
