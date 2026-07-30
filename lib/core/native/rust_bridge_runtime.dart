import 'generated/api/health.dart' as health_api;
import 'generated/frb_generated.dart';

/// Initializes and validates the one process-wide flutter_rust_bridge runtime.
///
/// Geometry, PSGC, and experimental image adapters share this guard so
/// concurrent first use cannot initialize the same native library twice.
class RustBridgeRuntime {
  RustBridgeRuntime._();

  static Future<void>? _initialization;

  static Future<void> ensureInitialized() async {
    final initialization = _initialization ??= _initialize();
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  static Future<void> _initialize() async {
    await RustLib.init();
    final health = await health_api.bridgeHealth();
    if (health.apiVersion != 2 ||
        health.implementation != 'voltrike-core-rust') {
      throw StateError(
        'Unexpected Rust bridge ${health.implementation} '
        'API ${health.apiVersion}.',
      );
    }
  }
}
