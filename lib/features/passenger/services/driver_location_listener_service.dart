import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../data/models/driver.dart';
import '../../../data/repositories/driver_repository.dart';

/// ===========================================================================
/// Driver Location Listener Service
///
/// Listens to the assigned driver's live location.
///
/// Used by:
/// • DriverTrackingScreen
/// • PassengerTripScreen
///
/// Flow:
///
/// Driver GPS
///        ↓
/// DriverRepository
///        ↓
/// Firestore
///        ↓
/// Stream??Driver??
///        ↓
/// LatLng
/// ===========================================================================
class DriverLocationListenerService {
  DriverLocationListenerService._();

  static final DriverLocationListenerService
      instance =
      DriverLocationListenerService._();

  final DriverRepository
      _driverRepository =
      DriverRepository();

  Stream<LatLng?> listen(
    String driverId,
  ) {
    return _driverRepository
        .driverStream(
          driverId,
        )
        .map(
      (Driver? driver) {
        if (driver == null) {
          return null;
        }

        if (driver.currentLatitude ==
                null ||
            driver.currentLongitude ==
                null) {
          return null;
        }

        return LatLng(
          driver.currentLatitude!,
          driver.currentLongitude!,
        );
      },
    );
  }
}