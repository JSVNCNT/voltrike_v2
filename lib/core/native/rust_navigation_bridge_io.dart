import 'dart:io';

import 'generated/api/navigation.dart' as navigation_api;
import 'rust_bridge_runtime.dart';
import 'rust_navigation_bridge_contract.dart';

RustNavigationBridge createRustNavigationBridge() =>
    GeneratedRustNavigationBridge();

class GeneratedRustNavigationBridge implements RustNavigationBridge {
  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<ActiveRouteInstallResponse> installRoute(
    String encodedPolyline,
  ) async {
    await _ensureInitialized();
    final result = await navigation_api.installActiveRoute(
      encodedPolyline: encodedPolyline,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'active route installation',
    );
    return ActiveRouteInstallResponse(
      routeGeneration: result.routeGeneration,
      pointCount: result.pointCount,
      segmentCount: result.segmentCount,
      totalDistanceMeters: result.totalDistanceMeters,
    );
  }

  @override
  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  }) async {
    await _ensureInitialized();
    final result = await navigation_api.processActiveRouteSamples(
      samples: samples
          .map(
            (sample) => navigation_api.NavigationGpsSample(
              latitude: sample.latitude,
              longitude: sample.longitude,
              accuracyMeters: sample.accuracyMeters,
              timestampMillis: sample.timestampMillis,
            ),
          )
          .toList(growable: false),
      expectedRouteGeneration: expectedRouteGeneration,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'active route GPS processing',
    );
    return ActiveRouteBatchResponse(
      routeGeneration: result.routeGeneration,
      acceptedCount: result.acceptedCount,
      rejectedCount: result.rejectedCount,
      samples: result.samples
          .map(
            (sample) => ActiveRouteSampleResponse(
              inputIndex: sample.inputIndex,
              disposition: _disposition(sample.disposition),
              filteredLatitude: sample.filteredLatitude,
              filteredLongitude: sample.filteredLongitude,
              nearestSegmentIndex: sample.nearestSegmentIndex,
              distanceFromRouteMeters: sample.distanceFromRouteMeters,
              routeProgressMeters: sample.routeProgressMeters,
              remainingDistanceMeters: sample.remainingDistanceMeters,
              routeHeadingDegrees: sample.routeHeadingDegrees,
              offRouteConfidence: sample.offRouteConfidence,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<ActiveRouteClearResponse> clearRoute(
    int expectedRouteGeneration,
  ) async {
    await _ensureInitialized();
    final result = await navigation_api.clearActiveRoute(
      expectedRouteGeneration: expectedRouteGeneration,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'active route cleanup',
    );
    return ActiveRouteClearResponse(routeGeneration: result.routeGeneration);
  }

  Future<void> _ensureInitialized() async {
    if (!isSupported) {
      throw UnsupportedError(
        'The VolTrike Rust navigation bridge is supported on Android only.',
      );
    }
    await RustBridgeRuntime.ensureInitialized();
  }

  static ActiveRouteSampleDisposition _disposition(
    navigation_api.NavigationSampleDisposition disposition,
  ) {
    return switch (disposition) {
      navigation_api.NavigationSampleDisposition.accepted =>
        ActiveRouteSampleDisposition.accepted,
      navigation_api.NavigationSampleDisposition.invalidCoordinates =>
        ActiveRouteSampleDisposition.invalidCoordinates,
      navigation_api.NavigationSampleDisposition.invalidAccuracy =>
        ActiveRouteSampleDisposition.invalidAccuracy,
      navigation_api.NavigationSampleDisposition.invalidTimestamp =>
        ActiveRouteSampleDisposition.invalidTimestamp,
      navigation_api.NavigationSampleDisposition.stale =>
        ActiveRouteSampleDisposition.stale,
      navigation_api.NavigationSampleDisposition.implausibleMotion =>
        ActiveRouteSampleDisposition.implausibleMotion,
    };
  }

  static void _throwUnlessOk({
    required navigation_api.NavigationRouteStatus status,
    required String? message,
    required String operation,
  }) {
    if (status == navigation_api.NavigationRouteStatus.ok) return;
    throw StateError(message ?? 'Rust rejected the $operation ($status).');
  }
}
