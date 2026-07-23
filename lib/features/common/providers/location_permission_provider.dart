import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/geolocation_service.dart';

/// ===========================================================================
/// Location Permission Provider
///
/// Exposes whether the application currently has
/// permission to access the device location.
/// ===========================================================================
final locationPermissionProvider =
    FutureProvider<bool>((ref) async {
  return GeolocationService.hasPermission();
});

/// ===========================================================================
/// Refresh Location Permission
///
/// Call:
///
/// ref.invalidate(locationPermissionProvider);
///
/// after requesting permission to update the UI.
/// ===========================================================================