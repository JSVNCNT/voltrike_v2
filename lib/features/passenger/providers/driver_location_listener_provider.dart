import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/driver_location_listener_service.dart';

/// ===========================================================================
/// Driver Location Listener Provider
///
/// Listens to the assigned driver's live location.
///
/// Firestore
/// drivers/{driverId}
///
/// Used by:
/// • DriverTrackingScreen
/// • PassengerTripScreen
/// ===========================================================================
final driverLocationListenerProvider =
    StreamProvider.family<
        LatLng?,
        String>(
  (
    ref,
    driverId,
  ) {
    return DriverLocationListenerService
        .instance
        .listen(
          driverId,
        );
  },
);