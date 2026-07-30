class RustRouteConflictRequest {
  const RustRouteConflictRequest({
    required this.routeLatLng,
    required this.polygonLatLng,
    required this.areaPointCounts,
    required this.restrictionAreaCounts,
  });

  final List<double> routeLatLng;
  final List<double> polygonLatLng;
  final List<int> areaPointCounts;
  final List<int> restrictionAreaCounts;
}

class RustRouteConflictResponse {
  const RustRouteConflictResponse({
    required this.conflictingRestrictionIndices,
  });

  final List<int> conflictingRestrictionIndices;
}

class RustRestrictionCacheRequest {
  const RustRestrictionCacheRequest({
    required this.polygonLatLng,
    required this.areaPointCounts,
    required this.restrictionAreaCounts,
  });

  final List<double> polygonLatLng;
  final List<int> areaPointCounts;
  final List<int> restrictionAreaCounts;
}

class RustRestrictionCacheResponse {
  const RustRestrictionCacheResponse({
    required this.cacheGeneration,
    required this.restrictionCount,
  });

  final int cacheGeneration;
  final int restrictionCount;
}

class RustEncodedRouteConflictRequest {
  const RustEncodedRouteConflictRequest({
    required this.encodedPolyline,
    required this.expectedCacheGeneration,
  });

  final String encodedPolyline;
  final int expectedCacheGeneration;
}

class RustCachedRouteConflictResponse {
  const RustCachedRouteConflictResponse({
    required this.cacheGeneration,
    required this.conflictingRestrictionIndices,
  });

  final int cacheGeneration;
  final List<int> conflictingRestrictionIndices;
}

class RustPointProximityRequest {
  const RustPointProximityRequest({
    required this.latitude,
    required this.longitude,
    required this.expectedCacheGeneration,
    this.preferredRestrictionIndex,
  });

  final double latitude;
  final double longitude;
  final int expectedCacheGeneration;
  final int? preferredRestrictionIndex;
}

class RustPointProximityResponse {
  const RustPointProximityResponse({
    required this.cacheGeneration,
    this.insideRestrictionIndex,
    this.nearestRestrictionIndex,
    this.nearestDistanceMeters,
    this.preferredDistanceMeters,
  });

  final int cacheGeneration;
  final int? insideRestrictionIndex;
  final int? nearestRestrictionIndex;
  final double? nearestDistanceMeters;
  final double? preferredDistanceMeters;
}

abstract interface class RustGeometryBridge {
  bool get isSupported;

  Future<RustRouteConflictResponse> analyzeRouteConflicts(
    RustRouteConflictRequest request,
  );

  Future<RustRestrictionCacheResponse> replaceRestrictionCache(
    RustRestrictionCacheRequest request,
  );

  Future<RustCachedRouteConflictResponse> analyzeCachedEncodedRouteConflicts(
    RustEncodedRouteConflictRequest request,
  );

  Future<RustPointProximityResponse> queryCachedPointProximity(
    RustPointProximityRequest request,
  );
}
