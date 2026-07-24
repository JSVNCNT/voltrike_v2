import 'package:flutter/material.dart';

/// ===========================================================================
/// Trip Information Card
///
/// Displays trip details.
///
/// Used by:
/// • DriverTrackingScreen
/// • PassengerTripScreen
/// • TripReceiptScreen
/// ===========================================================================
class TripInformationCard extends StatelessWidget {
  const TripInformationCard({
    super.key,
    required this.pickup,
    required this.destination,
    required this.distance,
    required this.duration,
    required this.fare,
  });

  final String pickup;
  final String destination;
  final String distance;
  final String duration;
  final String fare;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.zero,
              leading: const Icon(
                Icons.location_on,
              ),
              title: const Text(
                'Pickup',
              ),
              subtitle: Text(
                pickup,
              ),
            ),

            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.zero,
              leading:
                  const Icon(Icons.flag),
              title: const Text(
                'Destination',
              ),
              subtitle: Text(
                destination,
              ),
            ),

            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.zero,
              leading:
                  const Icon(Icons.route),
              title: const Text(
                'Distance',
              ),
              subtitle: Text(
                distance,
              ),
            ),

            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.zero,
              leading: const Icon(
                Icons.schedule,
              ),
              title: const Text(
                'Duration',
              ),
              subtitle: Text(
                duration,
              ),
            ),

            ListTile(
              dense: true,
              contentPadding:
                  EdgeInsets.zero,
              leading: const Icon(
                Icons.payments,
              ),
              title: const Text(
                'Estimated Fare',
              ),
              subtitle: Text(
                fare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}