import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';

/// ===========================================================================
/// Passenger Location Provider
///
/// Provides:
/// • Current GPS location
/// • Continuous location updates
///
/// Uses:
/// • LocationService
/// ===========================================================================
class PassengerLocationNotifier extends StateNotifier<AsyncValue<Position>> {
  PassengerLocationNotifier() : super(const AsyncLoading()) {
    _initialize();
  }

  StreamSubscription<Position>? _subscription;

  Future<void> _initialize() async {
    try {
      await LocationService.instance.ensurePermission();

      final current = await LocationService.instance.getCurrentLocation();

      state = AsyncData(current);

      await LocationService.instance.startTracking();

      _subscription = LocationService.instance.locationStream.listen(
        (position) {
          state = AsyncData(position);
        },
        onError: (Object error, StackTrace stackTrace) {
          state = AsyncError(error, stackTrace);
        },
      );
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }

  Future<void> refresh() async {
    final current = await LocationService.instance.getCurrentLocation();

    state = AsyncData(current);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // This notifier owns passenger foreground tracking. Do not allow the
    // singleton geolocation source to survive provider invalidation/logout.
    unawaited(LocationService.instance.stopTracking());
    super.dispose();
  }
}

/// ===========================================================================
/// Passenger Location Provider
/// ===========================================================================
final passengerLocationProvider =
    StateNotifierProvider<PassengerLocationNotifier, AsyncValue<Position>>(
      (ref) => PassengerLocationNotifier(),
    );
