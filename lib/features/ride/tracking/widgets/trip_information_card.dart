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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Trip details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _LocationDetail(
              icon: Icons.trip_origin_rounded,
              label: 'Pickup',
              value: pickup,
              iconColor: colorScheme.primary,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Container(
                width: 2,
                height: 16,
                color: colorScheme.outlineVariant,
              ),
            ),
            _LocationDetail(
              icon: Icons.flag_rounded,
              label: 'Destination',
              value: destination,
              iconColor: colorScheme.error,
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TripMetric(
                  icon: Icons.route_outlined,
                  label: 'Distance',
                  value: distance,
                ),
                _TripMetric(
                  icon: Icons.schedule_outlined,
                  label: 'Duration',
                  value: duration,
                ),
                _TripMetric(
                  icon: Icons.payments_outlined,
                  label: 'Estimated fare',
                  value: fare,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationDetail extends StatelessWidget {
  const _LocationDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _readable(value, 'Location unavailable'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TripMetric extends StatelessWidget {
  const _TripMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _readable(value, 'Updating…'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _readable(String value, String fallback) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized == '--') return fallback;
  return normalized;
}
