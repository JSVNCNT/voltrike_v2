import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';

/// ===========================================================================
/// Trip Status Card
///
/// Reusable booking status widget.
///
/// Used by:
/// • SearchingDriverScreen
/// • DriverTrackingScreen
/// • PassengerTripScreen
/// ===========================================================================
class TripStatusCard extends StatelessWidget {
  const TripStatusCard({
    super.key,
    required this.status,
    this.eta,
    this.distance,
  });

  final BookingStatus status;
  final String? eta;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final icon = _icon(status);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _title(status),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              _message(status),
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),

            if (eta != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ETA: $eta',
                  ),
                ],
              ),
            ],

            if (distance != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.route,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    distance!,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            Chip(
              backgroundColor: color,
              label: Text(
                status.name,
                style: const TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return Icons.search;

      case BookingStatus.driverAssigned:
        return Icons.person_pin_circle;

      case BookingStatus.driverArriving:
        return Icons.directions_car;

      case BookingStatus.passengerOnBoard:
        return Icons.route;

      case BookingStatus.completed:
        return Icons.check_circle;

      case BookingStatus.cancelled:
        return Icons.cancel;
    }
  }

  Color _color(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.orange;

      case BookingStatus.driverAssigned:
        return Colors.blue;

      case BookingStatus.driverArriving:
        return Colors.green;

      case BookingStatus.passengerOnBoard:
        return Colors.indigo;

      case BookingStatus.completed:
        return Colors.teal;

      case BookingStatus.cancelled:
        return Colors.red;
    }
  }

  String _title(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return 'Searching for Driver';

      case BookingStatus.driverAssigned:
        return 'Driver Assigned';

      case BookingStatus.driverArriving:
        return 'Driver Arriving';

      case BookingStatus.passengerOnBoard:
        return 'Trip in Progress';

      case BookingStatus.completed:
        return 'Trip Completed';

      case BookingStatus.cancelled:
        return 'Booking Cancelled';
    }
  }

  String _message(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return 'Please wait while we find a nearby driver.';

      case BookingStatus.driverAssigned:
        return 'A driver has accepted your booking.';

      case BookingStatus.driverArriving:
        return 'Your driver is heading to the pickup location.';

      case BookingStatus.passengerOnBoard:
        return 'Enjoy your ride.';

      case BookingStatus.completed:
        return 'Thank you for riding with VolTrike.';

      case BookingStatus.cancelled:
        return 'This booking has been cancelled.';
    }
  }
}