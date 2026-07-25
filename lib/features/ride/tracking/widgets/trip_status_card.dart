import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';
import '../models/ride_participant_role.dart';
import '../services/ride_status_service.dart';

/// Role-aware status summary for an active booking.
class TripStatusCard extends StatelessWidget {
  const TripStatusCard({
    super.key,
    required this.status,
    required this.role,
    this.eta,
    this.distance,
  });

  final BookingStatus status;
  final RideParticipantRole role;
  final String? eta;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final rideStatus = role == RideParticipantRole.driver
        ? RideStatusService.driverStatus(status)
        : RideStatusService.passengerStatus(status);
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(rideStatus.icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rideStatus.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(rideStatus.description),
            if (eta != null || distance != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (eta != null) _Metric(icon: Icons.schedule, text: 'ETA: $eta'),
                  if (distance != null)
                    _Metric(icon: Icons.route, text: distance!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }
}
