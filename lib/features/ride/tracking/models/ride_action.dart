import 'package:flutter/material.dart';

/// ===========================================================================
/// Ride Primary Action
///
/// Represents the primary action shown at the bottom of the ride screen.
///
/// This enum is UI-only.
/// It does NOT know anything about BookingStatus.
/// ===========================================================================
enum RidePrimaryAction {
  none,

  arriveAtPickup,

  startTrip,

  dropOffPassenger,

  completeTrip,

  cancelRide,

  rateDriver,

  viewReceipt,
}

extension RidePrimaryActionExtension on RidePrimaryAction {
  String get title {
    switch (this) {
      case RidePrimaryAction.none:
        return '';

      case RidePrimaryAction.arriveAtPickup:
        return 'Arrived at Pickup';

      case RidePrimaryAction.startTrip:
        return 'Start Trip';

      case RidePrimaryAction.dropOffPassenger:
        return 'Drop Off Passenger';

      case RidePrimaryAction.completeTrip:
        return 'Confirm Cash Received';

      case RidePrimaryAction.cancelRide:
        return 'Cancel Ride';

      case RidePrimaryAction.rateDriver:
        return 'Rate Driver';

      case RidePrimaryAction.viewReceipt:
        return 'View Receipt';
    }
  }

  IconData get icon {
    switch (this) {
      case RidePrimaryAction.none:
        return Icons.circle;

      case RidePrimaryAction.arriveAtPickup:
        return Icons.location_on;

      case RidePrimaryAction.startTrip:
        return Icons.play_arrow;

      case RidePrimaryAction.dropOffPassenger:
        return Icons.location_on;

      case RidePrimaryAction.completeTrip:
        return Icons.flag;

      case RidePrimaryAction.cancelRide:
        return Icons.cancel;

      case RidePrimaryAction.rateDriver:
        return Icons.star;

      case RidePrimaryAction.viewReceipt:
        return Icons.receipt_long;
    }
  }
}
