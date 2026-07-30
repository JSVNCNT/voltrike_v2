import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/booking.dart';
import '../services/booking_listener_service.dart';

/// ===========================================================================
/// Booking Listener Provider
///
/// Provides a realtime Firestore stream for a booking.
///
/// Used by:
/// • SearchingDriverScreen
/// • DriverAssignedScreen
/// • PassengerTripScreen
/// ===========================================================================
final bookingListenerProvider = StreamProvider.autoDispose
    .family<Booking?, String>((ref, bookingId) {
      return BookingListenerService.listen(bookingId);
    });
