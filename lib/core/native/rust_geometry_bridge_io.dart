import 'generated/api/geometry.dart' as geometry_api;
import 'native_rust_platform.dart';
import 'rust_bridge_runtime.dart';
import 'rust_geometry_bridge_contract.dart';

RustGeometryBridge createRustGeometryBridge() => GeneratedRustGeometryBridge();

class GeneratedRustGeometryBridge implements RustGeometryBridge {
  @override
  bool get isSupported => supportsNativeRust;

  @override
  Future<RustRouteConflictResponse> analyzeRouteConflicts(
    RustRouteConflictRequest request,
  ) async {
    await _ensureInitialized();
    final result = await geometry_api.analyzeRouteConflicts(
      routeLatLng: request.routeLatLng,
      polygonLatLng: request.polygonLatLng,
      areaPointCounts: request.areaPointCounts,
      restrictionAreaCounts: request.restrictionAreaCounts,
    );
    if (result.status != geometry_api.GeometryBatchStatus.ok) {
      throw StateError(
        result.errorMessage ?? 'Rust rejected the geometry batch.',
      );
    }
    return RustRouteConflictResponse(
      conflictingRestrictionIndices: result.conflictingRestrictionIndices,
    );
  }

  @override
  Future<RustRestrictionCacheResponse> replaceRestrictionCache(
    RustRestrictionCacheRequest request,
  ) async {
    await _ensureInitialized();
    final result = await geometry_api.replaceRestrictionCache(
      polygonLatLng: request.polygonLatLng,
      areaPointCounts: request.areaPointCounts,
      restrictionAreaCounts: request.restrictionAreaCounts,
    );
    _throwUnlessCacheOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'restriction cache update',
    );
    return RustRestrictionCacheResponse(
      cacheGeneration: result.cacheGeneration,
      restrictionCount: result.restrictionCount,
    );
  }

  @override
  Future<RustCachedRouteConflictResponse> analyzeCachedEncodedRouteConflicts(
    RustEncodedRouteConflictRequest request,
  ) async {
    await _ensureInitialized();
    final result = await geometry_api.analyzeCachedEncodedRouteConflicts(
      encodedPolyline: request.encodedPolyline,
      expectedCacheGeneration: request.expectedCacheGeneration,
    );
    _throwUnlessCacheOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'cached encoded route analysis',
    );
    return RustCachedRouteConflictResponse(
      cacheGeneration: result.cacheGeneration,
      conflictingRestrictionIndices: result.conflictingRestrictionIndices,
    );
  }

  @override
  Future<RustPointProximityResponse> queryCachedPointProximity(
    RustPointProximityRequest request,
  ) async {
    await _ensureInitialized();
    final result = await geometry_api.queryCachedPointProximity(
      latitude: request.latitude,
      longitude: request.longitude,
      expectedCacheGeneration: request.expectedCacheGeneration,
      preferredRestrictionIndex: request.preferredRestrictionIndex,
    );
    _throwUnlessCacheOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'cached point proximity query',
    );
    return RustPointProximityResponse(
      cacheGeneration: result.cacheGeneration,
      insideRestrictionIndex: result.insideRestrictionIndex,
      nearestRestrictionIndex: result.nearestRestrictionIndex,
      nearestDistanceMeters: result.nearestDistanceMeters,
      preferredDistanceMeters: result.preferredDistanceMeters,
    );
  }

  Future<void> _ensureInitialized() async {
    if (!isSupported) {
      throw UnsupportedError(
        'The VolTrike Rust geometry bridge is supported on Android only.',
      );
    }
    await RustBridgeRuntime.ensureInitialized();
  }

  static void _throwUnlessCacheOk({
    required geometry_api.GeometryCacheStatus status,
    required String? message,
    required String operation,
  }) {
    if (status == geometry_api.GeometryCacheStatus.ok) return;
    throw StateError(message ?? 'Rust rejected the $operation ($status).');
  }
}
