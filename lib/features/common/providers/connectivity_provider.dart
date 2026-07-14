import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';

/// ===========================================================================
/// Connectivity Provider
///
/// Provides the current internet connectivity state.
///
/// Returns:
/// • true  -> Internet available
/// • false -> No internet
/// ===========================================================================
final connectivityProvider =
    StreamProvider<bool>(
  (ref) =>
      ConnectivityService.connectivityStream,
);