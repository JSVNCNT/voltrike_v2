import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../providers/nearby_driver_provider.dart';

/// ===========================================================================
/// Nearby Driver Service
///
/// Responsible for retrieving available drivers.
///
/// Future:
/// • Firestore realtime listener
/// • Driver availability
/// • Driver online status
/// • Distance filtering
/// • TODA filtering
/// ===========================================================================
class NearbyDriverService {
  const NearbyDriverService._();

  /// =========================================================================
  /// Get Nearby Drivers
  /// =========================================================================
  ///
  /// Temporary implementation.
  ///
  /// Later this will query Firestore.
  static Future<List<NearbyDriver>>
      getNearbyDrivers({
    required LatLng passengerLocation,
    double radiusMeters = 5000,
  }) async {

    // Replace with Firestore query.

    return const [];
  }

  /// =========================================================================
  /// Driver Availability
  /// =========================================================================

  static Future<bool> isDriverAvailable(
    String driverId,
  ) async {
  
    // Firestore lookup.

    return true;
  }

  /// =========================================================================
  /// Refresh Nearby Drivers
  /// =========================================================================

  static Future<List<NearbyDriver>>
      refreshDrivers({
    required LatLng passengerLocation,
  }) {
    return getNearbyDrivers(
      passengerLocation:
          passengerLocation,
    );
  }
}
