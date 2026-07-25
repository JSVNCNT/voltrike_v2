import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';

import '../models/ride_status.dart';

class RideStatusService {
  const RideStatusService._();

  static RideStatus driverStatus(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return const RideStatus(
          title: 'Waiting',
          description: 'Waiting for booking assignment.',
          icon: Icons.hourglass_empty,
        );

      case BookingStatus.driverAssigned:
        return const RideStatus(
          title: 'Pickup',
          description: 'Proceed to the passenger pickup location.',
          icon: Icons.navigation,
        );

      case BookingStatus.driverArriving:
        return const RideStatus(
          title: 'Passenger Ready',
          description: 'Wait for the passenger before starting the trip.',
          icon: Icons.person_pin_circle,
        );

      case BookingStatus.passengerOnBoard:
        return const RideStatus(
          title: 'Trip Started',
          description: 'Navigate to the destination.',
          icon: Icons.directions,
        );

      case BookingStatus.completed:
        return const RideStatus(
          title: 'Completed',
          description: 'Trip completed successfully.',
          icon: Icons.check_circle,
        );

      case BookingStatus.cancelled:
        return const RideStatus(
          title: 'Cancelled',
          description: 'This booking has been cancelled.',
          icon: Icons.cancel,
        );
    }
  }

  static RideStatus passengerStatus(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return const RideStatus(
          title: 'Searching',
          description: 'Looking for an available driver.',
          icon: Icons.search,
        );

      case BookingStatus.driverAssigned:
        return const RideStatus(
          title: 'Driver Assigned',
          description: 'Your driver is heading to your pickup location.',
          icon: Icons.local_taxi,
        );

      case BookingStatus.driverArriving:
        return const RideStatus(
          title: 'Driver Arriving',
          description: 'Your driver is almost at the pickup point.',
          icon: Icons.location_on,
        );

      case BookingStatus.passengerOnBoard:
        return const RideStatus(
          title: 'On the Way',
          description: 'Enjoy your trip.',
          icon: Icons.directions_car,
        );

      case BookingStatus.completed:
        return const RideStatus(
          title: 'Trip Completed',
          description: 'Thank you for riding with VolTrike.',
          icon: Icons.check_circle,
        );

      case BookingStatus.cancelled:
        return const RideStatus(
          title: 'Cancelled',
          description: 'This booking has been cancelled.',
          icon: Icons.cancel,
        );
    }
  }
}