import 'package:connectivity_plus/connectivity_plus.dart';

/// ===========================================================================
/// Connectivity Service
///
/// Handles internet connectivity throughout the application.
/// ===========================================================================
class ConnectivityService {
  const ConnectivityService._();

  static final Connectivity _connectivity =
      Connectivity();

  /// =========================================================================
  /// Current Connectivity
  /// =========================================================================

  static Future<bool> hasConnection() async {
    final results =
        await _connectivity.checkConnectivity();

    return results.any(
      (result) =>
          result != ConnectivityResult.none,
    );
  }

  /// =========================================================================
  /// Connectivity Stream
  /// =========================================================================

  static Stream<bool> get connectivityStream =>
      _connectivity.onConnectivityChanged.map(
        (results) => results.any(
          (result) =>
              result != ConnectivityResult.none,
        ),
      );
}