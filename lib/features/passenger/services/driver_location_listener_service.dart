import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_database/firebase_database.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

/// Listens to an assigned driver's current RTDB location.
///
/// Firestore owns durable booking state. RTDB owns high-frequency coordinates
/// at `driver_locations/{driverId}`. Animation belongs to the map layer; this
/// stream emits at most one accepted point per real GPS observation.
class DriverLocationListenerService {
  DriverLocationListenerService._();

  static final DriverLocationListenerService instance =
      DriverLocationListenerService._();

  final FirebaseDatabase _database = FirebaseDatabase.instance;

  Stream<LatLng?> listen(String driverId) {
    return listenSamples(driverId).map((sample) => sample?.location);
  }

  Stream<DriverLocationSample?> listenSamples(String driverId) {
    final output = StreamController<DriverLocationSample?>();
    final filter = DriverLocationSampleFilter();
    late final StreamSubscription<DatabaseEvent> subscription;

    subscription = _database
        .ref('driver_locations/$driverId')
        .onValue
        .listen(
          (event) {
            final value = event.snapshot.value;
            if (value is! Map) {
              filter.reset();
              output.add(null);
              return;
            }

            final data = Map<Object?, Object?>.from(value);
            if (data['online'] == false) {
              filter.reset();
              output.add(null);
              return;
            }

            final sample = DriverLocationSample.tryParse(data);
            if (sample == null) {
              output.add(null);
              return;
            }

            switch (filter.evaluate(sample)) {
              case DriverLocationSampleDecision.emit:
                output.add(sample);
              case DriverLocationSampleDecision.suppress:
                break;
              case DriverLocationSampleDecision.reject:
                output.add(null);
            }
          },
          onError: output.addError,
          onDone: output.close,
        );

    output.onCancel = subscription.cancel;
    return output.stream;
  }
}

class DriverLocationSample {
  const DriverLocationSample({
    required this.location,
    required this.accuracyMeters,
    required this.observedAt,
    required this.publishedAt,
  });

  final LatLng location;
  final double accuracyMeters;

  /// Device-provided GPS time, used only to order distinct observations.
  final DateTime observedAt;

  /// Server-provided RTDB publication time, used to decide freshness.
  final DateTime publishedAt;

  static DriverLocationSample? tryParse(Map<Object?, Object?> data) {
    final latitude = _finiteDouble(data['latitude']);
    final longitude = _finiteDouble(data['longitude']);
    final accuracy = _finiteDouble(data['accuracy']);
    final timestampMillis = _finiteMillis(data['timestamp']);
    final observedAtMillis =
        _finiteMillis(data['observedAt']) ?? timestampMillis;
    final publishedAtMillis =
        timestampMillis ?? _finiteMillis(data['updatedAt']) ?? observedAtMillis;
    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        observedAtMillis == null ||
        publishedAtMillis == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        accuracy < 0 ||
        accuracy > DriverLocationSampleFilter.maximumAccuracyMeters) {
      return null;
    }

    try {
      return DriverLocationSample(
        location: LatLng(latitude, longitude),
        accuracyMeters: accuracy,
        observedAt: DateTime.fromMillisecondsSinceEpoch(
          observedAtMillis,
          isUtc: true,
        ),
        publishedAt: DateTime.fromMillisecondsSinceEpoch(
          publishedAtMillis,
          isUtc: true,
        ),
      );
    } on ArgumentError {
      return null;
    }
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  static int? _finiteMillis(Object? value) {
    final number = _finiteDouble(value);
    return number?.round();
  }
}

enum DriverLocationSampleDecision {
  /// The sample is valid and moved far enough to update the marker.
  emit,

  /// The sample is ordered but insignificant, or is an old/repeated heartbeat.
  suppress,

  /// The server publication time is stale or implausibly in the future.
  reject,
}

class DriverLocationSampleFilter {
  DriverLocationSampleFilter({
    this.maximumAge = const Duration(seconds: 45),
    this.minimumMovementMeters = 1,
  });

  static const double maximumAccuracyMeters = 100;

  final Duration maximumAge;
  final double minimumMovementMeters;

  DateTime? _lastObservedAt;
  LatLng? _lastEmittedLocation;

  DriverLocationSampleDecision evaluate(
    DriverLocationSample sample, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final age = currentTime.difference(sample.publishedAt);
    if (age > maximumAge || age < const Duration(seconds: -5)) {
      return DriverLocationSampleDecision.reject;
    }
    if (_lastObservedAt != null &&
        !sample.observedAt.isAfter(_lastObservedAt!)) {
      return DriverLocationSampleDecision.suppress;
    }

    _lastObservedAt = sample.observedAt;
    final previous = _lastEmittedLocation;
    if (previous != null &&
        _distanceMeters(previous, sample.location) < minimumMovementMeters) {
      return DriverLocationSampleDecision.suppress;
    }
    _lastEmittedLocation = sample.location;
    return DriverLocationSampleDecision.emit;
  }

  bool shouldEmit(DriverLocationSample sample, {DateTime? now}) {
    return evaluate(sample, now: now) == DriverLocationSampleDecision.emit;
  }

  void reset() {
    _lastObservedAt = null;
    _lastEmittedLocation = null;
  }

  static double _distanceMeters(LatLng start, LatLng end) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(end.latitude - start.latitude);
    final longitudeDelta = _radians(end.longitude - start.longitude);
    final startLatitude = _radians(start.latitude);
    final endLatitude = _radians(end.latitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(startLatitude) *
            math.cos(endLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
