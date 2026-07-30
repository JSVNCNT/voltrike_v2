import 'rust_navigation_bridge_contract.dart';

RustNavigationBridge createRustNavigationBridge() =>
    const UnsupportedRustNavigationBridge();

class UnsupportedRustNavigationBridge implements RustNavigationBridge {
  const UnsupportedRustNavigationBridge();

  @override
  bool get isSupported => false;

  @override
  Future<ActiveRouteInstallResponse> installRoute(String encodedPolyline) {
    return _unsupported();
  }

  @override
  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  }) {
    return _unsupported();
  }

  @override
  Future<ActiveRouteClearResponse> clearRoute(int expectedRouteGeneration) {
    return _unsupported();
  }

  Future<T> _unsupported<T>() {
    return Future<T>.error(
      UnsupportedError(
        'The VolTrike Rust navigation bridge is supported on Android only.',
      ),
    );
  }
}
