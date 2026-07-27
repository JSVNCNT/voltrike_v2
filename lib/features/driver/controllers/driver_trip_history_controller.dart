import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';

/// ===========================================================================
/// Repository
/// ===========================================================================

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(),
);

/// ===========================================================================
/// Driver Trip History Controller
/// ===========================================================================

class DriverTripHistoryController {
  DriverTripHistoryController(this._bookingRepository, this._authRepository);

  final BookingRepository _bookingRepository;
  final AuthRepository _authRepository;

  Stream<List<Booking>> tripHistory() {
    final user = _authRepository.currentUser;

    if (user == null) {
      return Stream.value([]);
    }

    return _bookingRepository
        .bookingsForDriver(user.uid)
        .map(BookingStateMachine.terminalHistory);
  }
}

/// ===========================================================================
/// Controller Provider
/// ===========================================================================

final driverTripHistoryControllerProvider =
    Provider<DriverTripHistoryController>((ref) {
      return DriverTripHistoryController(
        ref.watch(bookingRepositoryProvider),
        AuthRepository(),
      );
    });

/// ===========================================================================
/// Trips Provider
/// ===========================================================================

final driverTripHistoryProvider = StreamProvider<List<Booking>>((ref) {
  return ref.watch(driverTripHistoryControllerProvider).tripHistory();
});
