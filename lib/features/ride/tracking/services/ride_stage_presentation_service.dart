import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';
import '../models/ride_action.dart';
import '../models/ride_participant_role.dart';
import '../models/ride_status.dart';

class RideStagePresentation {
  const RideStagePresentation({
    required this.status,
    required this.primaryAction,
    this.allowContact = false,
    this.allowCancel = false,
    this.allowReport = false,
    this.allowSos = false,
    this.allowNoShow = false,
  });

  final RideStatus status;
  final RidePrimaryAction primaryAction;
  final bool allowContact;
  final bool allowCancel;
  final bool allowReport;
  final bool allowSos;
  final bool allowNoShow;
}

/// Canonical status-to-copy/action policy for both ride participants.
class RideStagePresentationService {
  const RideStagePresentationService._();

  static RideStagePresentation resolve({
    required RideParticipantRole role,
    required BookingStatus status,
  }) {
    return role == RideParticipantRole.driver
        ? _driver(status)
        : _passenger(status);
  }

  static RideStagePresentation _driver(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Waiting',
            description: 'Waiting for a booking assignment.',
            icon: Icons.hourglass_empty,
          ),
          primaryAction: RidePrimaryAction.none,
        );
      case BookingStatus.driverAssigned:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Drive to Pickup',
            description: 'Proceed to the passenger pickup location.',
            icon: Icons.navigation,
          ),
          primaryAction: RidePrimaryAction.arriveAtPickup,
          allowContact: true,
          allowCancel: true,
          allowReport: true,
        );
      case BookingStatus.driverArriving:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'At Pickup',
            description: 'Wait for the passenger before starting the trip.',
            icon: Icons.person_pin_circle,
          ),
          primaryAction: RidePrimaryAction.startTrip,
          allowContact: true,
          allowCancel: true,
          allowReport: true,
          allowNoShow: true,
        );
      case BookingStatus.passengerOnBoard:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Trip in Progress',
            description: 'Navigate to the passenger destination.',
            icon: Icons.directions,
          ),
          primaryAction: RidePrimaryAction.dropOffPassenger,
          allowReport: true,
          allowSos: true,
        );
      case BookingStatus.paymentConfirmation:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Payment Confirmation',
            description: 'Confirm the cash received to complete this trip.',
            icon: Icons.payments,
          ),
          primaryAction: RidePrimaryAction.completeTrip,
          allowReport: true,
        );
      case BookingStatus.completed:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Trip Completed',
            description: 'The trip and driver earnings are recorded.',
            icon: Icons.check_circle,
          ),
          primaryAction: RidePrimaryAction.viewReceipt,
        );
      case BookingStatus.cancelled:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Ride Cancelled',
            description: 'This booking is closed.',
            icon: Icons.cancel,
          ),
          primaryAction: RidePrimaryAction.none,
        );
    }
  }

  static RideStagePresentation _passenger(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Searching for a Driver',
            description: 'Looking for an available nearby driver.',
            icon: Icons.search,
          ),
          primaryAction: RidePrimaryAction.cancelRide,
          allowCancel: true,
        );
      case BookingStatus.driverAssigned:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Driver Assigned',
            description: 'Your driver is heading to the pickup.',
            icon: Icons.local_taxi,
          ),
          primaryAction: RidePrimaryAction.cancelRide,
          allowContact: true,
          allowCancel: true,
          allowReport: true,
        );
      case BookingStatus.driverArriving:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Driver at Pickup',
            description: 'Meet your driver at the selected pickup point.',
            icon: Icons.location_on,
          ),
          primaryAction: RidePrimaryAction.cancelRide,
          allowContact: true,
          allowCancel: true,
          allowReport: true,
        );
      case BookingStatus.passengerOnBoard:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'On the Way',
            description: 'Your ride is heading to the destination.',
            icon: Icons.directions_car,
          ),
          primaryAction: RidePrimaryAction.none,
          allowReport: true,
          allowSos: true,
        );
      case BookingStatus.paymentConfirmation:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Payment Confirmation',
            description: 'Waiting for the driver to confirm cash received.',
            icon: Icons.payments,
          ),
          primaryAction: RidePrimaryAction.none,
          allowReport: true,
        );
      case BookingStatus.completed:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Trip Completed',
            description: 'Rate your driver and review the receipt.',
            icon: Icons.check_circle,
          ),
          primaryAction: RidePrimaryAction.rateDriver,
        );
      case BookingStatus.cancelled:
        return const RideStagePresentation(
          status: RideStatus(
            title: 'Ride Cancelled',
            description: 'This booking is closed.',
            icon: Icons.cancel,
          ),
          primaryAction: RidePrimaryAction.none,
        );
    }
  }
}
