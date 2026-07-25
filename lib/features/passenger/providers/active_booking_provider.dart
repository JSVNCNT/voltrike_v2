import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';

/// The authenticated passenger's recoverable active booking.
///
/// This provider is intentionally Firestore-backed: it restores the durable
/// ride lifecycle, while the tracking screen separately consumes live RTDB
/// location updates for the assigned driver.
final activePassengerBookingProvider = StreamProvider<Booking?>((ref) {
  final user = AuthRepository().currentUser;

  if (user == null) {
    return Stream<Booking?>.value(null);
  }

  return BookingRepository().activeBookingForPassenger(user.uid);
});
