import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  const ConnectivityService._();

  static final Connectivity _connectivity = Connectivity();

  static Future<bool> hasConnection() async {
    final result = await _connectivity.checkConnectivity();

    return result.any(
      (type) => type != ConnectivityResult.none,
    );
  }

  static Stream<List<ConnectivityResult>> get stream =>
      _connectivity.onConnectivityChanged;
}