import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../maps/voltrike_map.dart';
import '../services/polyline_service.dart';
import 'rust_migration_mode.dart';
import 'rust_navigation_bridge.dart';

const int _maximumBatchSamples = 256;
const int _maximumFallbackReplaySamples = 32;
const double _maximumAcceptedAccuracyMeters = 100;
const int _maximumSampleAgeMillis = 30000;
const double _maximumPlausibleSpeedMetersPerSecond = 75;
const double _motionAccuracyAllowanceMultiplier = 2;
const double _offRouteBaseThresholdMeters = 25;
const double _offRouteConfidenceRangeMeters = 100;
const double _offRouteEmaAlpha = 0.35;
const double _metersPerDegree = 111320;
const double _minimumSegmentLengthMeters = 0.01;

/// Pure-Dart implementation used as the authority in `off`, as the comparison
/// baseline in `shadow`, and as a lazily initialized fallback in `on`.
class DartActiveRouteProcessor implements ActiveRouteProcessor {
  int _generation = 0;
  List<_RouteSegment>? _segments;
  double _totalDistanceMeters = 0;
  _NavigationTracker _tracker = const _NavigationTracker();

  @override
  Future<ActiveRouteInstallResponse> installRoute(
    String encodedPolyline,
  ) async {
    final points = PolylineService.decodePolyline(encodedPolyline);
    if (points.length < 2) {
      throw const FormatException(
        'Active route must contain at least two points.',
      );
    }

    final segments = <_RouteSegment>[];
    var totalDistanceMeters = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      final lengthMeters = _haversineDistanceMeters(start, end);
      if (!lengthMeters.isFinite) {
        throw const FormatException(
          'Active route contains a non-finite segment length.',
        );
      }
      if (lengthMeters < _minimumSegmentLengthMeters) continue;
      segments.add(
        _RouteSegment(
          start: start,
          end: end,
          lengthMeters: lengthMeters,
          cumulativeStartMeters: totalDistanceMeters,
          headingDegrees: _initialBearingDegrees(start, end),
        ),
      );
      totalDistanceMeters += lengthMeters;
    }
    if (segments.isEmpty || !totalDistanceMeters.isFinite) {
      throw const FormatException(
        'Active route must contain at least one non-zero segment.',
      );
    }

    final nextGeneration = _generation + 1;
    if (nextGeneration <= 0 || nextGeneration > 0xffffffff) {
      throw StateError('Active route generation is exhausted.');
    }
    _segments = List.unmodifiable(segments);
    _totalDistanceMeters = totalDistanceMeters;
    _tracker = const _NavigationTracker();
    _generation = nextGeneration;
    return ActiveRouteInstallResponse(
      routeGeneration: nextGeneration,
      pointCount: points.length,
      segmentCount: segments.length,
      totalDistanceMeters: totalDistanceMeters,
    );
  }

  @override
  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  }) async {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'Must not be empty.');
    }
    if (samples.length > _maximumBatchSamples) {
      throw ArgumentError.value(
        samples.length,
        'samples.length',
        'Exceeds the $_maximumBatchSamples item limit.',
      );
    }
    final segments = _segments;
    if (expectedRouteGeneration <= 0) {
      throw ArgumentError.value(
        expectedRouteGeneration,
        'expectedRouteGeneration',
        'Must be non-zero.',
      );
    }
    if (expectedRouteGeneration != _generation) {
      throw StateError(
        'Active route generation mismatch: expected '
        '$expectedRouteGeneration, actual $_generation.',
      );
    }
    if (segments == null) {
      throw StateError('Active route is unavailable.');
    }

    int? newestTimestampMillis;
    for (final sample in samples) {
      if (sample.timestampMillis <= 0) continue;
      if (newestTimestampMillis == null ||
          sample.timestampMillis > newestTimestampMillis) {
        newestTimestampMillis = sample.timestampMillis;
      }
    }

    final responses = <ActiveRouteSampleResponse>[];
    var acceptedCount = 0;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final disposition = _validateSample(sample, newestTimestampMillis);
      if (disposition != ActiveRouteSampleDisposition.accepted) {
        responses.add(
          ActiveRouteSampleResponse(
            inputIndex: index,
            disposition: disposition,
          ),
        );
        continue;
      }

      final rawPoint = LatLng(sample.latitude, sample.longitude);
      final filteredPoint = _smoothPoint(
        _tracker.filteredPoint,
        rawPoint,
        sample.accuracyMeters,
      );
      final nearest = _nearestRoutePoint(filteredPoint, segments);
      final segment = segments[nearest.segmentIndex];
      final progressMeters =
          (segment.cumulativeStartMeters +
                  segment.lengthMeters * nearest.projection)
              .clamp(0.0, _totalDistanceMeters);
      final remainingDistanceMeters = math.max(
        0.0,
        _totalDistanceMeters - progressMeters,
      );
      final instantaneousConfidence = _offRouteConfidence(
        nearest.distanceMeters,
        sample.accuracyMeters,
      );
      final smoothedConfidence = _tracker.lastTimestampMillis == null
          ? instantaneousConfidence
          : _offRouteEmaAlpha * instantaneousConfidence +
                (1 - _offRouteEmaAlpha) * _tracker.offRouteConfidence;
      _tracker = _NavigationTracker(
        lastTimestampMillis: sample.timestampMillis,
        lastRawPoint: rawPoint,
        lastRawAccuracyMeters: sample.accuracyMeters,
        filteredPoint: filteredPoint,
        offRouteConfidence: smoothedConfidence,
      );
      acceptedCount++;
      responses.add(
        ActiveRouteSampleResponse(
          inputIndex: index,
          disposition: ActiveRouteSampleDisposition.accepted,
          filteredLatitude: filteredPoint.latitude,
          filteredLongitude: filteredPoint.longitude,
          nearestSegmentIndex: nearest.segmentIndex,
          distanceFromRouteMeters: nearest.distanceMeters,
          routeProgressMeters: progressMeters,
          remainingDistanceMeters: remainingDistanceMeters,
          routeHeadingDegrees: segment.headingDegrees,
          offRouteConfidence: smoothedConfidence,
        ),
      );
    }

    return ActiveRouteBatchResponse(
      routeGeneration: _generation,
      acceptedCount: acceptedCount,
      rejectedCount: responses.length - acceptedCount,
      samples: List.unmodifiable(responses),
    );
  }

  @override
  Future<ActiveRouteClearResponse> clearRoute(
    int expectedRouteGeneration,
  ) async {
    if (expectedRouteGeneration <= 0) {
      throw ArgumentError.value(
        expectedRouteGeneration,
        'expectedRouteGeneration',
        'Must be non-zero.',
      );
    }
    if (expectedRouteGeneration != _generation) {
      throw StateError(
        'Active route generation mismatch: expected '
        '$expectedRouteGeneration, actual $_generation.',
      );
    }
    if (_segments == null) {
      throw StateError('Active route is already clear.');
    }
    _segments = null;
    _totalDistanceMeters = 0;
    _tracker = const _NavigationTracker();
    return ActiveRouteClearResponse(routeGeneration: _generation);
  }

  ActiveRouteSampleDisposition _validateSample(
    ActiveRouteGpsSample sample,
    int? newestTimestampMillis,
  ) {
    if (!_validCoordinates(sample.latitude, sample.longitude)) {
      return ActiveRouteSampleDisposition.invalidCoordinates;
    }
    if (!sample.accuracyMeters.isFinite ||
        sample.accuracyMeters < 0 ||
        sample.accuracyMeters > _maximumAcceptedAccuracyMeters) {
      return ActiveRouteSampleDisposition.invalidAccuracy;
    }
    if (sample.timestampMillis <= 0) {
      return ActiveRouteSampleDisposition.invalidTimestamp;
    }
    final lastTimestampMillis = _tracker.lastTimestampMillis;
    if (lastTimestampMillis != null &&
        sample.timestampMillis <= lastTimestampMillis) {
      return ActiveRouteSampleDisposition.stale;
    }
    if (newestTimestampMillis != null &&
        newestTimestampMillis - sample.timestampMillis >
            _maximumSampleAgeMillis) {
      return ActiveRouteSampleDisposition.stale;
    }

    final lastRawPoint = _tracker.lastRawPoint;
    final lastRawAccuracyMeters = _tracker.lastRawAccuracyMeters;
    if (lastRawPoint != null &&
        lastTimestampMillis != null &&
        lastRawAccuracyMeters != null) {
      final elapsedMillis = sample.timestampMillis - lastTimestampMillis;
      if (elapsedMillis > 0) {
        final distanceMeters = _haversineDistanceMeters(
          lastRawPoint,
          LatLng(sample.latitude, sample.longitude),
        );
        final accuracyAllowance =
            (lastRawAccuracyMeters + sample.accuracyMeters) *
            _motionAccuracyAllowanceMultiplier;
        final plausibleDistance =
            _maximumPlausibleSpeedMetersPerSecond * (elapsedMillis / 1000.0) +
            accuracyAllowance;
        if (distanceMeters > plausibleDistance) {
          return ActiveRouteSampleDisposition.implausibleMotion;
        }
      }
    }
    return ActiveRouteSampleDisposition.accepted;
  }
}

/// Rollout coordinator that preserves Dart as the safe implementation while
/// enabling measured Rust adoption through `VOLTRIKE_NAVIGATION_MODE`.
class ActiveRouteNavigationEngine {
  ActiveRouteNavigationEngine({
    RustMigrationMode? mode,
    RustNavigationBridge? rustBridge,
    DartActiveRouteProcessor? dartProcessor,
    void Function(String message)? reporter,
  }) : mode = mode ?? RustMigrationMode.navigationFromEnvironment(),
       _rustBridge = rustBridge ?? createRustNavigationBridge(),
       _dartProcessor = dartProcessor ?? DartActiveRouteProcessor(),
       _reporter = reporter ?? debugPrint;

  final RustMigrationMode mode;
  final RustNavigationBridge _rustBridge;
  final DartActiveRouteProcessor _dartProcessor;
  final void Function(String message) _reporter;

  int? _dartGeneration;
  int? _rustGeneration;
  bool _rustUsable = false;
  String? _encodedPolyline;
  final List<ActiveRouteGpsSample> _fallbackReplay = <ActiveRouteGpsSample>[];

  Future<ActiveRouteInstallResponse> installRoute(
    String encodedPolyline,
  ) async {
    _encodedPolyline = encodedPolyline;
    _fallbackReplay.clear();
    _dartGeneration = null;
    _rustGeneration = null;
    _rustUsable = false;

    if (mode == RustMigrationMode.off || !_rustBridge.isSupported) {
      final dart = await _dartProcessor.installRoute(encodedPolyline);
      _dartGeneration = dart.routeGeneration;
      return dart;
    }

    if (mode == RustMigrationMode.on) {
      try {
        final rust = await _rustBridge.installRoute(encodedPolyline);
        _rustGeneration = rust.routeGeneration;
        _rustUsable = true;
        return rust;
      } catch (error) {
        _reporter('Rust active-route install fallback: $error');
        return _installDartFallback();
      }
    }

    final dart = await _dartProcessor.installRoute(encodedPolyline);
    _dartGeneration = dart.routeGeneration;
    try {
      final rust = await _rustBridge.installRoute(encodedPolyline);
      _rustGeneration = rust.routeGeneration;
      _rustUsable = true;
      if (!_installMatches(dart, rust)) {
        _reporter(
          'Rust active-route shadow mismatch while installing the route.',
        );
      }
      return dart;
    } catch (error) {
      _reporter('Rust active-route install fallback: $error');
      return dart;
    }
  }

  Future<ActiveRouteBatchResponse> processSamples(
    List<ActiveRouteGpsSample> samples,
  ) async {
    if (_encodedPolyline == null) {
      throw StateError('Install an active route before processing GPS.');
    }

    if (mode == RustMigrationMode.on && _rustBridge.isSupported) {
      final rustGeneration = _rustGeneration;
      if (_rustUsable && rustGeneration != null) {
        try {
          final rust = await _rustBridge.processSamples(
            samples: samples,
            expectedRouteGeneration: rustGeneration,
          );
          _retainForFallback(samples, rust);
          return rust;
        } catch (error) {
          _rustUsable = false;
          _reporter('Rust active-route GPS fallback: $error');
          await _activateDartFallback();
        }
      } else if (_dartGeneration == null) {
        await _activateDartFallback();
      }
      return _processWithDart(samples);
    }

    final dart = await _processWithDart(samples);
    final rustGeneration = _rustGeneration;
    if (mode != RustMigrationMode.shadow ||
        !_rustBridge.isSupported ||
        !_rustUsable ||
        rustGeneration == null) {
      return dart;
    }

    try {
      final rust = await _rustBridge.processSamples(
        samples: samples,
        expectedRouteGeneration: rustGeneration,
      );
      if (!_batchMatches(dart, rust)) {
        _reporter(
          'Rust active-route shadow mismatch while processing GPS samples.',
        );
      }
      return dart;
    } catch (error) {
      _rustUsable = false;
      _reporter('Rust active-route GPS fallback: $error');
      return dart;
    }
  }

  Future<void> clearRoute() async {
    final dartGeneration = _dartGeneration;
    final rustGeneration = _rustGeneration;
    _dartGeneration = null;
    _rustGeneration = null;
    _rustUsable = false;
    _encodedPolyline = null;
    _fallbackReplay.clear();

    Object? dartError;
    if (dartGeneration != null) {
      try {
        await _dartProcessor.clearRoute(dartGeneration);
      } catch (error) {
        dartError = error;
      }
    }
    if (mode != RustMigrationMode.off &&
        _rustBridge.isSupported &&
        rustGeneration != null) {
      try {
        await _rustBridge.clearRoute(rustGeneration);
      } catch (error) {
        _reporter('Rust active-route clear fallback: $error');
      }
    }
    if (dartError != null) throw dartError;
  }

  Future<ActiveRouteInstallResponse> _installDartFallback() async {
    final encodedPolyline = _encodedPolyline;
    if (encodedPolyline == null) {
      throw StateError('Install an active route before processing GPS.');
    }
    final dart = await _dartProcessor.installRoute(encodedPolyline);
    _dartGeneration = dart.routeGeneration;
    return dart;
  }

  Future<void> _activateDartFallback() async {
    if (_dartGeneration != null) return;
    await _installDartFallback();

    final replay = List<ActiveRouteGpsSample>.of(_fallbackReplay);
    _fallbackReplay.clear();
    for (final sample in replay) {
      await _processWithDart(<ActiveRouteGpsSample>[sample]);
    }
  }

  Future<ActiveRouteBatchResponse> _processWithDart(
    List<ActiveRouteGpsSample> samples,
  ) {
    final generation = _dartGeneration;
    if (generation == null) {
      throw StateError('Dart active-route fallback is unavailable.');
    }
    return _dartProcessor.processSamples(
      samples: samples,
      expectedRouteGeneration: generation,
    );
  }

  void _retainForFallback(
    List<ActiveRouteGpsSample> samples,
    ActiveRouteBatchResponse response,
  ) {
    final accepted = <ActiveRouteGpsSample>[
      for (final result in response.samples)
        if (result.isAccepted &&
            result.inputIndex >= 0 &&
            result.inputIndex < samples.length)
          samples[result.inputIndex],
    ];
    if (accepted.length >= _maximumFallbackReplaySamples) {
      _fallbackReplay
        ..clear()
        ..addAll(
          accepted.skip(accepted.length - _maximumFallbackReplaySamples),
        );
      return;
    }
    final overflow =
        _fallbackReplay.length +
        accepted.length -
        _maximumFallbackReplaySamples;
    if (overflow > 0) {
      _fallbackReplay.removeRange(0, overflow);
    }
    _fallbackReplay.addAll(accepted);
  }

  static bool _installMatches(
    ActiveRouteInstallResponse dart,
    ActiveRouteInstallResponse rust,
  ) {
    return dart.pointCount == rust.pointCount &&
        dart.segmentCount == rust.segmentCount &&
        (dart.totalDistanceMeters - rust.totalDistanceMeters).abs() <= 1;
  }

  static bool _batchMatches(
    ActiveRouteBatchResponse dart,
    ActiveRouteBatchResponse rust,
  ) {
    if (dart.acceptedCount != rust.acceptedCount ||
        dart.rejectedCount != rust.rejectedCount ||
        dart.samples.length != rust.samples.length) {
      return false;
    }
    for (var index = 0; index < dart.samples.length; index++) {
      final left = dart.samples[index];
      final right = rust.samples[index];
      if (left.inputIndex != right.inputIndex ||
          left.disposition != right.disposition ||
          left.nearestSegmentIndex != right.nearestSegmentIndex ||
          !_close(left.filteredLatitude, right.filteredLatitude, 0.000001) ||
          !_close(left.filteredLongitude, right.filteredLongitude, 0.000001) ||
          !_close(
            left.distanceFromRouteMeters,
            right.distanceFromRouteMeters,
            1,
          ) ||
          !_close(left.routeProgressMeters, right.routeProgressMeters, 1) ||
          !_close(
            left.remainingDistanceMeters,
            right.remainingDistanceMeters,
            1,
          ) ||
          !_close(left.routeHeadingDegrees, right.routeHeadingDegrees, 0.5) ||
          !_close(left.offRouteConfidence, right.offRouteConfidence, 0.02)) {
        return false;
      }
    }
    return true;
  }

  static bool _close(double? left, double? right, double tolerance) {
    if (left == null || right == null) return left == right;
    return (left - right).abs() <= tolerance;
  }
}

class _NavigationTracker {
  const _NavigationTracker({
    this.lastTimestampMillis,
    this.lastRawPoint,
    this.lastRawAccuracyMeters,
    this.filteredPoint,
    this.offRouteConfidence = 0,
  });

  final int? lastTimestampMillis;
  final LatLng? lastRawPoint;
  final double? lastRawAccuracyMeters;
  final LatLng? filteredPoint;
  final double offRouteConfidence;
}

class _RouteSegment {
  const _RouteSegment({
    required this.start,
    required this.end,
    required this.lengthMeters,
    required this.cumulativeStartMeters,
    required this.headingDegrees,
  });

  final LatLng start;
  final LatLng end;
  final double lengthMeters;
  final double cumulativeStartMeters;
  final double headingDegrees;
}

class _NearestRoutePoint {
  const _NearestRoutePoint({
    required this.segmentIndex,
    required this.distanceMeters,
    required this.projection,
  });

  final int segmentIndex;
  final double distanceMeters;
  final double projection;
}

_NearestRoutePoint _nearestRoutePoint(
  LatLng point,
  List<_RouteSegment> segments,
) {
  _NearestRoutePoint? nearest;
  for (var index = 0; index < segments.length; index++) {
    final projection = _projectOntoSegment(point, segments[index]);
    if (nearest == null || projection.distanceMeters < nearest.distanceMeters) {
      nearest = _NearestRoutePoint(
        segmentIndex: index,
        distanceMeters: projection.distanceMeters,
        projection: projection.projection,
      );
    }
  }
  if (nearest == null) {
    throw StateError('Active route has no queryable segments.');
  }
  return nearest;
}

_NearestRoutePoint _projectOntoSegment(LatLng point, _RouteSegment segment) {
  final referenceLatitude =
      (point.latitude + segment.start.latitude + segment.end.latitude) /
      3 *
      math.pi /
      180;
  final longitudeScale = _metersPerDegree * math.cos(referenceLatitude).abs();
  final pointX = (point.longitude - segment.start.longitude) * longitudeScale;
  final pointY = (point.latitude - segment.start.latitude) * _metersPerDegree;
  final segmentX =
      (segment.end.longitude - segment.start.longitude) * longitudeScale;
  final segmentY =
      (segment.end.latitude - segment.start.latitude) * _metersPerDegree;
  final lengthSquared = segmentX * segmentX + segmentY * segmentY;
  if (lengthSquared <= double.minPositive) {
    return _NearestRoutePoint(
      segmentIndex: 0,
      distanceMeters: math.sqrt(pointX * pointX + pointY * pointY),
      projection: 0,
    );
  }
  final projection = ((pointX * segmentX + pointY * segmentY) / lengthSquared)
      .clamp(0.0, 1.0);
  final deltaX = pointX - segmentX * projection;
  final deltaY = pointY - segmentY * projection;
  return _NearestRoutePoint(
    segmentIndex: 0,
    distanceMeters: math.sqrt(deltaX * deltaX + deltaY * deltaY),
    projection: projection,
  );
}

LatLng _smoothPoint(LatLng? previous, LatLng current, double accuracyMeters) {
  if (previous == null) return current;
  final alpha = (20 / (accuracyMeters + 20)).clamp(0.15, 0.75);
  return LatLng(
    previous.latitude + (current.latitude - previous.latitude) * alpha,
    previous.longitude + (current.longitude - previous.longitude) * alpha,
  );
}

double _offRouteConfidence(double distanceMeters, double accuracyMeters) {
  final threshold = _offRouteBaseThresholdMeters + math.max(0, accuracyMeters);
  return ((distanceMeters - threshold) / _offRouteConfidenceRangeMeters).clamp(
    0.0,
    1.0,
  );
}

bool _validCoordinates(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

double _haversineDistanceMeters(LatLng first, LatLng second) {
  const earthRadiusMeters = 6371000.0;
  final firstLatitude = first.latitude * math.pi / 180;
  final secondLatitude = second.latitude * math.pi / 180;
  final latitudeDelta = (second.latitude - first.latitude) * math.pi / 180;
  final longitudeDelta = (second.longitude - first.longitude) * math.pi / 180;
  final sinLatitude = math.sin(latitudeDelta / 2);
  final sinLongitude = math.sin(longitudeDelta / 2);
  final haversine =
      sinLatitude * sinLatitude +
      math.cos(firstLatitude) *
          math.cos(secondLatitude) *
          sinLongitude *
          sinLongitude;
  return 2 *
      earthRadiusMeters *
      math.asin(math.sqrt(haversine.clamp(0.0, 1.0)));
}

double _initialBearingDegrees(LatLng first, LatLng second) {
  final firstLatitude = first.latitude * math.pi / 180;
  final secondLatitude = second.latitude * math.pi / 180;
  final longitudeDelta = (second.longitude - first.longitude) * math.pi / 180;
  final y = math.sin(longitudeDelta) * math.cos(secondLatitude);
  final x =
      math.cos(firstLatitude) * math.sin(secondLatitude) -
      math.sin(firstLatitude) *
          math.cos(secondLatitude) *
          math.cos(longitudeDelta);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
