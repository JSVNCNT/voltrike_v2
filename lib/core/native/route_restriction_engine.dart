import 'package:flutter/foundation.dart';

import '../../data/models/route_restriction.dart';
import '../maps/voltrike_map.dart';
import '../services/polyline_service.dart';
import '../services/route_restriction_matcher.dart';
import 'rust_geometry_bridge.dart';
import 'rust_migration_mode.dart';

typedef RustMigrationReporter = void Function(String message);

class RouteRestrictionEngine {
  static const int maximumRoutePoints = 200000;
  static const int maximumPolygonPoints = 200000;
  static const int maximumRestrictions = 10000;
  static const int maximumAreas = 200000;
  static const int maximumGeometryWorkItems = 20000000;

  RouteRestrictionEngine({
    RustMigrationMode? mode,
    RustMigrationMode? proximityMode,
    RustGeometryBridge? rustBridge,
    RustMigrationReporter? reporter,
  }) : mode = mode ?? RustMigrationMode.geometryFromEnvironment(),
       proximityMode =
           proximityMode ??
           RustMigrationMode.geometryProximityFromEnvironment(),
       _rustBridge = rustBridge ?? createRustGeometryBridge(),
       _reporter = reporter ?? debugPrint;

  static final RouteRestrictionEngine instance = RouteRestrictionEngine();

  final RustMigrationMode mode;
  final RustMigrationMode proximityMode;
  final RustGeometryBridge _rustBridge;
  final RustMigrationReporter _reporter;
  _NativeRestrictionCache? _nativeCache;
  Future<_NativeRestrictionCache>? _cacheInstall;

  Future<int?> firstRouteConflictIndex({
    required List<LatLng> route,
    required List<RouteRestriction> restrictions,
  }) async {
    if (mode == RustMigrationMode.off || !_rustBridge.isSupported) {
      return _safeDartConflictIndex(route, restrictions);
    }

    if (mode == RustMigrationMode.shadow) {
      return _runShadow(route: route, restrictions: restrictions);
    }

    try {
      final packed = _pack(route, restrictions);
      final rustResponse = await _rustBridge.analyzeRouteConflicts(
        packed.request,
      );
      return _firstOriginalRestrictionIndex(
        rustResponse.conflictingRestrictionIndices,
        packed.originalRestrictionIndices,
      );
    } catch (error) {
      _reporter('Rust route restriction fallback: $error');
      return _safeDartConflictIndex(route, restrictions);
    }
  }

  Future<int?> firstEncodedRouteConflictIndex({
    required String encodedPolyline,
    required List<RouteRestriction> restrictions,
  }) async {
    if (encodedPolyline.length > PolylineService.maximumEncodedBytes) {
      throw StateError(
        'Encoded route exceeds the ${PolylineService.maximumEncodedBytes} '
        'byte safety limit.',
      );
    }
    if (mode == RustMigrationMode.off || !_rustBridge.isSupported) {
      return _safeDartEncodedConflictIndex(encodedPolyline, restrictions);
    }
    if (mode == RustMigrationMode.shadow) {
      return _runEncodedShadow(
        encodedPolyline: encodedPolyline,
        restrictions: restrictions,
      );
    }

    try {
      return await _firstRustEncodedConflictIndex(
        encodedPolyline: encodedPolyline,
        restrictions: restrictions,
      );
    } catch (error) {
      _reporter('Rust encoded route restriction fallback: $error');
      return _safeDartEncodedConflictIndex(encodedPolyline, restrictions);
    }
  }

  Future<RouteRestrictionProximity> pointProximity({
    required LatLng point,
    required List<RouteRestriction> restrictions,
    String? preferredRestrictionId,
  }) async {
    if (proximityMode == RustMigrationMode.off || !_rustBridge.isSupported) {
      return _safeDartPointProximity(
        point,
        restrictions,
        preferredRestrictionId: preferredRestrictionId,
      );
    }
    if (proximityMode == RustMigrationMode.shadow) {
      return _runProximityShadow(
        point: point,
        restrictions: restrictions,
        preferredRestrictionId: preferredRestrictionId,
      );
    }

    try {
      return await _rustPointProximity(
        point: point,
        restrictions: restrictions,
        preferredRestrictionId: preferredRestrictionId,
      );
    } catch (error) {
      _reporter('Rust restriction proximity fallback: $error');
      return _safeDartPointProximity(
        point,
        restrictions,
        preferredRestrictionId: preferredRestrictionId,
      );
    }
  }

  Future<int?> _runShadow({
    required List<LatLng> route,
    required List<RouteRestriction> restrictions,
  }) async {
    final dartStopwatch = Stopwatch()..start();
    final dartResult = _safeDartConflictIndex(route, restrictions);
    dartStopwatch.stop();

    try {
      final rustStopwatch = Stopwatch()..start();
      final packed = _pack(route, restrictions);
      final rustResponse = await _rustBridge.analyzeRouteConflicts(
        packed.request,
      );
      final rustResult = _firstOriginalRestrictionIndex(
        rustResponse.conflictingRestrictionIndices,
        packed.originalRestrictionIndices,
      );
      rustStopwatch.stop();
      _reporter(
        'Rust route restriction shadow: '
        'matched=${rustResult == dartResult} '
        'dart=$dartResult rust=$rustResult '
        'dartUs=${dartStopwatch.elapsedMicroseconds} '
        'rustUs=${rustStopwatch.elapsedMicroseconds} '
        'routePoints=${route.length} '
        'restrictions=${packed.originalRestrictionIndices.length}.',
      );
    } catch (error) {
      _reporter('Rust route restriction shadow fallback: $error');
    }
    return dartResult;
  }

  Future<int?> _runEncodedShadow({
    required String encodedPolyline,
    required List<RouteRestriction> restrictions,
  }) async {
    final dartStopwatch = Stopwatch()..start();
    final dartResult = _safeDartEncodedConflictIndex(
      encodedPolyline,
      restrictions,
    );
    dartStopwatch.stop();

    try {
      final rustStopwatch = Stopwatch()..start();
      final rustResult = await _firstRustEncodedConflictIndex(
        encodedPolyline: encodedPolyline,
        restrictions: restrictions,
      );
      rustStopwatch.stop();
      _reporter(
        'Rust encoded route restriction shadow: '
        'matched=${rustResult == dartResult} '
        'dart=$dartResult rust=$rustResult '
        'dartUs=${dartStopwatch.elapsedMicroseconds} '
        'rustUs=${rustStopwatch.elapsedMicroseconds} '
        'encodedBytes=${encodedPolyline.length}.',
      );
    } catch (error) {
      _reporter('Rust encoded route restriction shadow fallback: $error');
    }
    return dartResult;
  }

  Future<RouteRestrictionProximity> _runProximityShadow({
    required LatLng point,
    required List<RouteRestriction> restrictions,
    String? preferredRestrictionId,
  }) async {
    final dartStopwatch = Stopwatch()..start();
    final dartResult = _safeDartPointProximity(
      point,
      restrictions,
      preferredRestrictionId: preferredRestrictionId,
    );
    dartStopwatch.stop();

    try {
      final rustStopwatch = Stopwatch()..start();
      final rustResult = await _rustPointProximity(
        point: point,
        restrictions: restrictions,
        preferredRestrictionId: preferredRestrictionId,
      );
      rustStopwatch.stop();
      _reporter(
        'Rust restriction proximity shadow: '
        'matched=${_sameProximity(rustResult, dartResult)} '
        'dartInside=${dartResult.insideRestrictionIndex} '
        'rustInside=${rustResult.insideRestrictionIndex} '
        'dartNearest=${dartResult.nearestRestrictionIndex} '
        'rustNearest=${rustResult.nearestRestrictionIndex} '
        'dartUs=${dartStopwatch.elapsedMicroseconds} '
        'rustUs=${rustStopwatch.elapsedMicroseconds}.',
      );
    } catch (error) {
      _reporter('Rust restriction proximity shadow fallback: $error');
    }
    return dartResult;
  }

  Future<int?> _firstRustEncodedConflictIndex({
    required String encodedPolyline,
    required List<RouteRestriction> restrictions,
  }) async {
    final cache = await _ensureNativeCache(restrictions);
    try {
      final response = await _rustBridge.analyzeCachedEncodedRouteConflicts(
        RustEncodedRouteConflictRequest(
          encodedPolyline: encodedPolyline,
          expectedCacheGeneration: cache.generation,
        ),
      );
      _validateCacheGeneration(response.cacheGeneration, cache.generation);
      return _firstOriginalRestrictionIndex(
        response.conflictingRestrictionIndices,
        cache.originalRestrictionIndices,
      );
    } catch (_) {
      _invalidateNativeCacheIfCurrent(cache);
      rethrow;
    }
  }

  Future<RouteRestrictionProximity> _rustPointProximity({
    required LatLng point,
    required List<RouteRestriction> restrictions,
    String? preferredRestrictionId,
  }) async {
    final cache = await _ensureNativeCache(restrictions);
    try {
      final preferredRestrictionIndex = cache.nativeIndexForId(
        preferredRestrictionId,
      );
      final response = await _rustBridge.queryCachedPointProximity(
        RustPointProximityRequest(
          latitude: point.latitude,
          longitude: point.longitude,
          expectedCacheGeneration: cache.generation,
          preferredRestrictionIndex: preferredRestrictionIndex,
        ),
      );
      _validateCacheGeneration(response.cacheGeneration, cache.generation);
      final insideIndex = _originalRestrictionIndex(
        response.insideRestrictionIndex,
        cache.originalRestrictionIndices,
      );
      final nearestIndex = _originalRestrictionIndex(
        response.nearestRestrictionIndex,
        cache.originalRestrictionIndices,
      );
      _validateDistance(
        response.nearestDistanceMeters,
        fieldName: 'nearest distance',
      );
      _validateDistance(
        response.preferredDistanceMeters,
        fieldName: 'preferred distance',
      );
      if (preferredRestrictionIndex == null &&
          response.preferredDistanceMeters != null) {
        throw StateError(
          'Rust returned a distance for an unrequested preferred restriction.',
        );
      }
      if ((nearestIndex == null) != (response.nearestDistanceMeters == null)) {
        throw StateError(
          'Rust returned inconsistent nearest restriction proximity.',
        );
      }
      if (insideIndex != null &&
          (insideIndex != nearestIndex ||
              response.nearestDistanceMeters != 0.0)) {
        throw StateError('Rust returned inconsistent inside proximity.');
      }
      return RouteRestrictionProximity(
        insideRestrictionIndex: insideIndex,
        nearestRestrictionIndex: nearestIndex,
        nearestDistanceMeters: response.nearestDistanceMeters,
        preferredDistanceMeters: response.preferredDistanceMeters,
      );
    } catch (_) {
      _invalidateNativeCacheIfCurrent(cache);
      rethrow;
    }
  }

  Future<_NativeRestrictionCache> _ensureNativeCache(
    List<RouteRestriction> restrictions,
  ) async {
    final current = _nativeCache;
    if (current != null && current.matches(restrictions)) return current;

    final pending = _cacheInstall;
    if (pending != null) {
      final installed = await pending;
      if (installed.matches(restrictions)) return installed;
    }

    final packed = _packRestrictions(restrictions);
    late final Future<_NativeRestrictionCache> install;
    install = _replaceNativeCache(restrictions: restrictions, packed: packed);
    _cacheInstall = install;
    try {
      final installed = await install;
      _nativeCache = installed;
      return installed;
    } finally {
      if (identical(_cacheInstall, install)) _cacheInstall = null;
    }
  }

  Future<_NativeRestrictionCache> _replaceNativeCache({
    required List<RouteRestriction> restrictions,
    required _PackedRestrictions packed,
  }) async {
    final response = await _rustBridge.replaceRestrictionCache(
      RustRestrictionCacheRequest(
        polygonLatLng: packed.polygonLatLng,
        areaPointCounts: packed.areaPointCounts,
        restrictionAreaCounts: packed.restrictionAreaCounts,
      ),
    );
    if (response.cacheGeneration <= 0) {
      throw StateError('Rust returned an invalid cache generation.');
    }
    if (response.restrictionCount != packed.originalRestrictionIndices.length) {
      throw StateError(
        'Rust cached ${response.restrictionCount} restrictions, expected '
        '${packed.originalRestrictionIndices.length}.',
      );
    }
    return _NativeRestrictionCache(
      generation: response.cacheGeneration,
      sourceRestrictions: restrictions,
      sourceIdentitySignature: _restrictionIdentitySignature(restrictions),
      originalRestrictionIndices: List<int>.unmodifiable(
        packed.originalRestrictionIndices,
      ),
    );
  }

  void _invalidateNativeCacheIfCurrent(_NativeRestrictionCache cache) {
    if (identical(_nativeCache, cache)) {
      _nativeCache = null;
    }
  }

  static int? _safeDartEncodedConflictIndex(
    String encodedPolyline,
    List<RouteRestriction> restrictions,
  ) {
    final route = PolylineService.decodePolyline(
      encodedPolyline,
      maxEncodedBytes: PolylineService.maximumEncodedBytes,
      maxPoints: maximumRoutePoints,
    );
    return _safeDartConflictIndex(route, restrictions);
  }

  static int? _safeDartConflictIndex(
    List<LatLng> route,
    List<RouteRestriction> restrictions,
  ) {
    if (route.length > maximumRoutePoints) {
      throw StateError(
        'Route point count exceeds the $maximumRoutePoints item safety limit.',
      );
    }
    for (final point in route) {
      _validatePoint(point, label: 'route');
    }
    final polygonPointCount = _validateRestrictionsForDart(restrictions);
    if (route.length * polygonPointCount > maximumGeometryWorkItems) {
      throw StateError(
        'Route geometry exceeds the $maximumGeometryWorkItems work-item '
        'safety limit.',
      );
    }
    return _firstDartConflictIndex(route, restrictions);
  }

  static RouteRestrictionProximity _safeDartPointProximity(
    LatLng point,
    List<RouteRestriction> restrictions, {
    String? preferredRestrictionId,
  }) {
    _validatePoint(point, label: 'query');
    _validateRestrictionsForDart(restrictions);
    return RouteRestrictionMatcher.pointProximity(
      point,
      restrictions,
      preferredRestrictionId: preferredRestrictionId,
    );
  }

  static int _validateRestrictionsForDart(List<RouteRestriction> restrictions) {
    var enforcedRestrictionCount = 0;
    var areaCount = 0;
    var polygonPointCount = 0;
    for (final restriction in restrictions) {
      if (!RouteRestrictionMatcher.isEnforcedPolygon(restriction)) continue;
      enforcedRestrictionCount++;
      if (enforcedRestrictionCount > maximumRestrictions) {
        throw StateError(
          'Restriction count exceeds the $maximumRestrictions item safety '
          'limit.',
        );
      }
      areaCount += restriction.areas.length;
      if (areaCount > maximumAreas) {
        throw StateError(
          'Restriction area count exceeds the $maximumAreas item safety '
          'limit.',
        );
      }
      for (final area in restriction.areas) {
        polygonPointCount += area.length;
        if (polygonPointCount > maximumPolygonPoints) {
          throw StateError(
            'Polygon point count exceeds the $maximumPolygonPoints item '
            'safety limit.',
          );
        }
        for (final point in area) {
          _validatePoint(point, label: 'polygon');
        }
      }
    }
    return polygonPointCount;
  }

  static void _validatePoint(LatLng point, {required String label}) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude < -90 ||
        point.latitude > 90 ||
        point.longitude < -180 ||
        point.longitude > 180) {
      throw StateError('$label contains an invalid coordinate.');
    }
  }

  static int? _firstDartConflictIndex(
    List<LatLng> route,
    List<RouteRestriction> restrictions,
  ) {
    for (var index = 0; index < restrictions.length; index++) {
      if (RouteRestrictionMatcher.routeConflicts(route, restrictions[index])) {
        return index;
      }
    }
    return null;
  }

  static int? _firstOriginalRestrictionIndex(
    List<int> conflictingNativeIndices,
    List<int> originalRestrictionIndices,
  ) {
    if (conflictingNativeIndices.isEmpty) return null;

    int? firstOriginalIndex;
    for (final nativeIndex in conflictingNativeIndices) {
      if (nativeIndex < 0 || nativeIndex >= originalRestrictionIndices.length) {
        throw StateError(
          'Rust returned an out-of-range restriction index $nativeIndex.',
        );
      }
      final originalIndex = originalRestrictionIndices[nativeIndex];
      if (firstOriginalIndex == null || originalIndex < firstOriginalIndex) {
        firstOriginalIndex = originalIndex;
      }
    }
    return firstOriginalIndex;
  }

  static int? _originalRestrictionIndex(
    int? nativeIndex,
    List<int> originalRestrictionIndices,
  ) {
    if (nativeIndex == null) return null;
    if (nativeIndex < 0 || nativeIndex >= originalRestrictionIndices.length) {
      throw StateError(
        'Rust returned an out-of-range restriction index $nativeIndex.',
      );
    }
    return originalRestrictionIndices[nativeIndex];
  }

  static void _validateCacheGeneration(int actual, int expected) {
    if (actual <= 0 || actual != expected) {
      throw StateError(
        'Rust restriction cache generation changed '
        '(expected $expected, actual $actual).',
      );
    }
  }

  static void _validateDistance(double? value, {required String fieldName}) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw StateError('Rust returned an invalid $fieldName.');
    }
  }

  static bool _sameProximity(
    RouteRestrictionProximity left,
    RouteRestrictionProximity right,
  ) {
    return left.insideRestrictionIndex == right.insideRestrictionIndex &&
        left.nearestRestrictionIndex == right.nearestRestrictionIndex &&
        _sameDistance(
          left.nearestDistanceMeters,
          right.nearestDistanceMeters,
        ) &&
        _sameDistance(
          left.preferredDistanceMeters,
          right.preferredDistanceMeters,
        );
  }

  static bool _sameDistance(double? left, double? right) {
    if (left == null || right == null) return left == right;
    final scale = left.abs() > right.abs() ? left.abs() : right.abs();
    return (left - right).abs() <= 1e-6 * (scale < 1 ? 1 : scale);
  }

  static _PackedRouteRestrictions _pack(
    List<LatLng> route,
    List<RouteRestriction> restrictions,
  ) {
    final routeLatLng = <double>[];
    for (final point in route) {
      routeLatLng
        ..add(point.latitude)
        ..add(point.longitude);
    }

    final packedRestrictions = _packRestrictions(restrictions);
    return _PackedRouteRestrictions(
      request: RustRouteConflictRequest(
        routeLatLng: routeLatLng,
        polygonLatLng: packedRestrictions.polygonLatLng,
        areaPointCounts: packedRestrictions.areaPointCounts,
        restrictionAreaCounts: packedRestrictions.restrictionAreaCounts,
      ),
      originalRestrictionIndices: packedRestrictions.originalRestrictionIndices,
    );
  }

  static _PackedRestrictions _packRestrictions(
    List<RouteRestriction> restrictions,
  ) {
    final polygonLatLng = <double>[];
    final areaPointCounts = <int>[];
    final restrictionAreaCounts = <int>[];
    final originalRestrictionIndices = <int>[];

    for (var index = 0; index < restrictions.length; index++) {
      final restriction = restrictions[index];
      if (!RouteRestrictionMatcher.isEnforcedPolygon(restriction)) continue;

      originalRestrictionIndices.add(index);
      restrictionAreaCounts.add(restriction.areas.length);
      for (final area in restriction.areas) {
        areaPointCounts.add(area.length);
        for (final point in area) {
          polygonLatLng
            ..add(point.latitude)
            ..add(point.longitude);
        }
      }
    }

    return _PackedRestrictions(
      polygonLatLng: polygonLatLng,
      areaPointCounts: areaPointCounts,
      restrictionAreaCounts: restrictionAreaCounts,
      originalRestrictionIndices: originalRestrictionIndices,
    );
  }
}

class _PackedRouteRestrictions {
  const _PackedRouteRestrictions({
    required this.request,
    required this.originalRestrictionIndices,
  });

  final RustRouteConflictRequest request;
  final List<int> originalRestrictionIndices;
}

class _PackedRestrictions {
  const _PackedRestrictions({
    required this.polygonLatLng,
    required this.areaPointCounts,
    required this.restrictionAreaCounts,
    required this.originalRestrictionIndices,
  });

  final List<double> polygonLatLng;
  final List<int> areaPointCounts;
  final List<int> restrictionAreaCounts;
  final List<int> originalRestrictionIndices;
}

class _NativeRestrictionCache {
  const _NativeRestrictionCache({
    required this.generation,
    required this.sourceRestrictions,
    required this.sourceIdentitySignature,
    required this.originalRestrictionIndices,
  });

  final int generation;
  final List<RouteRestriction> sourceRestrictions;
  final int sourceIdentitySignature;
  final List<int> originalRestrictionIndices;

  bool matches(List<RouteRestriction> restrictions) {
    return identical(sourceRestrictions, restrictions) &&
        sourceRestrictions.length == restrictions.length &&
        sourceIdentitySignature == _restrictionIdentitySignature(restrictions);
  }

  int? nativeIndexForId(String? restrictionId) {
    if (restrictionId == null) return null;
    for (
      var nativeIndex = 0;
      nativeIndex < originalRestrictionIndices.length;
      nativeIndex++
    ) {
      final originalIndex = originalRestrictionIndices[nativeIndex];
      if (sourceRestrictions[originalIndex].id == restrictionId) {
        return nativeIndex;
      }
    }
    return null;
  }
}

int _restrictionIdentitySignature(List<RouteRestriction> restrictions) {
  return Object.hashAll(restrictions.map(identityHashCode));
}
