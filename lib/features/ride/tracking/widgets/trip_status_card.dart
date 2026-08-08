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
    this.compact = false,
  });

  final BookingStatus status;
  final RideParticipantRole role;
  final String? eta;
  final String? distance;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rideStatus = role == RideParticipantRole.driver
        ? RideStatusService.driverStatus(status)
        : RideStatusService.passengerStatus(status);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.58),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: compact ? 20 : 23,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: Icon(rideStatus.icon),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rideStatus.title,
                    style:
                        (compact
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.titleMedium)
                            ?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  SizedBox(height: compact ? 2 : 4),
                  Text(
                    rideStatus.description,
                    style:
                        (compact
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                              color: colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.82,
                              ),
                            ),
                  ),
                  if (eta != null || distance != null) ...[
                    SizedBox(height: compact ? 8 : 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (eta != null)
                          _Metric(
                            icon: Icons.schedule_rounded,
                            text: 'ETA $eta',
                          ),
                        if (distance != null)
                          _Metric(icon: Icons.route_rounded, text: distance!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
