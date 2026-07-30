import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_user.dart';

import '../services/passenger_listener_service.dart';

/// ===========================================================================
/// Passenger Listener Provider
///
/// Listens to the passenger profile for the active booking.
///
/// Firestore
/// users/{passengerId}
///
/// Used by:
/// • DriverBookingTrackingScreen
/// ===========================================================================
final passengerListenerProvider = StreamProvider.autoDispose
    .family<AppUser?, String>((ref, passengerId) {
      return PassengerListenerService.instance.listen(passengerId);
    });
