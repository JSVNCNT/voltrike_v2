import 'rust_geometry_bridge_contract.dart';

RustGeometryBridge createRustGeometryBridge() =>
    const UnsupportedRustGeometryBridge();

class UnsupportedRustGeometryBridge implements RustGeometryBridge {
  const UnsupportedRustGeometryBridge();

  @override
  bool get isSupported => false;

  @override
  Future<RustRouteConflictResponse> analyzeRouteConflicts(
    RustRouteConflictRequest request,
  ) {
    return _unsupported();
  }

  @override
  Future<RustRestrictionCacheResponse> replaceRestrictionCache(
    RustRestrictionCacheRequest request,
  ) {
    return _unsupported();
  }

  @override
  Future<RustCachedRouteConflictResponse> analyzeCachedEncodedRouteConflicts(
    RustEncodedRouteConflictRequest request,
  ) {
    return _unsupported();
  }

  @override
  Future<RustPointProximityResponse> queryCachedPointProximity(
    RustPointProximityRequest request,
  ) {
    return _unsupported();
  }

  Future<T> _unsupported<T>() {
    return Future<T>.error(
      UnsupportedError(
        'The VolTrike Rust geometry bridge is supported on Android only.',
      ),
    );
  }
}
