import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ===========================================================================
/// Current Passenger Booking
/// ===========================================================================
class CurrentBookingNotifier
    extends StateNotifier<String?> {
  CurrentBookingNotifier() : super(null);

  void setBooking(String bookingId) {
    state = bookingId;
  }

  void clearBooking() {
    state = null;
  }
}

final currentBookingProvider =
    StateNotifierProvider<
        CurrentBookingNotifier,
        String?>(
  (ref) => CurrentBookingNotifier(),
);