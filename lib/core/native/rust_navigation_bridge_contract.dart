enum ActiveRouteSampleDisposition {
  accepted,
  invalidCoordinates,
  invalidAccuracy,
  invalidTimestamp,
  stale,
  implausibleMotion,
}

class ActiveRouteGpsSample {
  const ActiveRouteGpsSample({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestampMillis,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final int timestampMillis;
}

class ActiveRouteInstallResponse {
  const ActiveRouteInstallResponse({
    required this.routeGeneration,
    required this.pointCount,
    required this.segmentCount,
    required this.totalDistanceMeters,
  });

  final int routeGeneration;
  final int pointCount;
  final int segmentCount;
  final double totalDistanceMeters;
}

class ActiveRouteSampleResponse {
  const ActiveRouteSampleResponse({
    required this.inputIndex,
    required this.disposition,
    this.filteredLatitude,
    this.filteredLongitude,
    this.nearestSegmentIndex,
    this.distanceFromRouteMeters,
    this.routeProgressMeters,
    this.remainingDistanceMeters,
    this.routeHeadingDegrees,
    this.offRouteConfidence,
  });

  final int inputIndex;
  final ActiveRouteSampleDisposition disposition;
  final double? filteredLatitude;
  final double? filteredLongitude;
  final int? nearestSegmentIndex;
  final double? distanceFromRouteMeters;
  final double? routeProgressMeters;
  final double? remainingDistanceMeters;
  final double? routeHeadingDegrees;
  final double? offRouteConfidence;

  bool get isAccepted => disposition == ActiveRouteSampleDisposition.accepted;
}

class ActiveRouteBatchResponse {
  const ActiveRouteBatchResponse({
    required this.routeGeneration,
    required this.acceptedCount,
    required this.rejectedCount,
    required this.samples,
  });

  final int routeGeneration;
  final int acceptedCount;
  final int rejectedCount;
  final List<ActiveRouteSampleResponse> samples;
}

class ActiveRouteClearResponse {
  const ActiveRouteClearResponse({required this.routeGeneration});

  final int routeGeneration;
}

abstract interface class ActiveRouteProcessor {
  Future<ActiveRouteInstallResponse> installRoute(String encodedPolyline);

  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  });

  Future<ActiveRouteClearResponse> clearRoute(int expectedRouteGeneration);
}

abstract interface class RustNavigationBridge implements ActiveRouteProcessor {
  bool get isSupported;
}
