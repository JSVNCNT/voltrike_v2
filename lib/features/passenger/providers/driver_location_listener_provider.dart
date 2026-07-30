import 'package:flutter_riverpod/flutter_riverpod.dart';

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
final driverLocationListenerProvider = StreamProvider.autoDispose
    .family<DriverLocationSample?, String>((ref, driverId) {
      return DriverLocationListenerService.instance.listenSamples(driverId);
    });
