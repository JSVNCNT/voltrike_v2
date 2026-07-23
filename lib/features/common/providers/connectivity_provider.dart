import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';

/// ===========================================================================
/// Connectivity Provider
///
/// Exposes the application's internet connection state.
///
/// true  -> Connected
/// false -> Offline
/// ===========================================================================
final connectivityProvider =
    StreamProvider<bool>(
  (ref) =>
      ConnectivityService.connectivityStream,
);