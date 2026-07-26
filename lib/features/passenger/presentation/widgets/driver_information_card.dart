import 'package:flutter/material.dart';

import '../../../common/presentation/widgets/star_rating.dart';

/// ===========================================================================
/// Driver Information Card
///
/// Displays information about the assigned driver.
///
/// This widget is intentionally presentation-only.
/// Ride actions (Call, Message, Report) are handled by RideActionsCard.
/// ===========================================================================
class DriverInformationCard extends StatelessWidget {
  const DriverInformationCard({
    super.key,
    required this.driverName,
    required this.vehicleNumber,
    required this.plateNumber,
    required this.todaName,
    this.photoUrl,
    this.rating,
  });

  final String driverName;
  final String vehicleNumber;
  final String plateNumber;
  final String todaName;
  final String? photoUrl;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: photoUrl?.trim().isNotEmpty == true
                  ? NetworkImage(photoUrl!)
                  : null,
              child: photoUrl?.trim().isNotEmpty == true
                  ? null
                  : const Icon(Icons.person, size: 32),
            ),

            const SizedBox(height: 12),

            Text(
              driverName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            if (rating != null) ...[
              const SizedBox(height: 8),

              StarRating(rating: rating!, size: 22),

              const SizedBox(height: 4),

              Text(
                '${rating!.toStringAsFixed(1)} / 5.0',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            const Divider(height: 32),

            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.electric_rickshaw),
              title: const Text('Vehicle'),
              subtitle: Text(vehicleNumber),
            ),

            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.confirmation_number),
              title: const Text('Plate Number'),
              subtitle: Text(plateNumber),
            ),

            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_city),
              title: const Text('TODA'),
              subtitle: Text(todaName),
            ),
          ],
        ),
      ),
    );
  }
}
