import '../../../../data/models/booking.dart';

import '../models/ride_action.dart';

/// ===========================================================================
/// Ride Action Service
///
/// Maps a BookingStatus into the primary action shown in the UI.
///
/// This service contains ONLY business rules.
/// ===========================================================================
class RideActionService {
  const RideActionService._();

  //==========================================================================
  // Driver
  //==========================================================================

  static RidePrimaryAction driverPrimaryAction(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return RidePrimaryAction.none;

      case BookingStatus.driverAssigned:
        return RidePrimaryAction.arriveAtPickup;

      case BookingStatus.driverArriving:
        return RidePrimaryAction.startTrip;

      case BookingStatus.passengerOnBoard:
        return RidePrimaryAction.completeTrip;

      case BookingStatus.completed:
        return RidePrimaryAction.viewReceipt;

      case BookingStatus.cancelled:
        return RidePrimaryAction.none;
    }
  }

  //==========================================================================
  // Passenger
  //==========================================================================

  static RidePrimaryAction passengerPrimaryAction(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return RidePrimaryAction.cancelRide;

      case BookingStatus.driverAssigned:
        return RidePrimaryAction.cancelRide;

      case BookingStatus.driverArriving:
        return RidePrimaryAction.cancelRide;

      case BookingStatus.passengerOnBoard:
        return RidePrimaryAction.none;

      case BookingStatus.completed:
        return RidePrimaryAction.rateDriver;

      case BookingStatus.cancelled:
        return RidePrimaryAction.none;
    }
  }

  //==========================================================================
  // Helpers
  //==========================================================================

  static bool showPrimaryButton(
    RidePrimaryAction action,
  ) {
    return action != RidePrimaryAction.none;
  }
}