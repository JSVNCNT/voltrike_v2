import 'package:flutter/material.dart';

import '../../../../core/theme/app_semantic_colors.dart';

/// ===========================================================================
/// Booking Request Card
///
/// Displays an incoming passenger booking.
///
/// Used in:
/// • DriverHomeScreen
/// • DriverBottomSheet
/// ===========================================================================
class BookingRequestCard extends StatelessWidget {
  const BookingRequestCard({
    super.key,
    required this.passengerName,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedFare,
    required this.distance,
    this.routeAdvisory = '',
    this.passengerPhotoUrl,
    this.onAccept,
    this.onDecline,
  });

  final String passengerName;
  final String pickupAddress;
  final String destinationAddress;
  final String estimatedFare;
  final String distance;
  final String routeAdvisory;
  final String? passengerPhotoUrl;

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = AppSemanticColors.of(context);

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'New ride request',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: colorScheme.primaryContainer,
                  backgroundImage: passengerPhotoUrl?.trim().isNotEmpty == true
                      ? NetworkImage(passengerPhotoUrl!)
                      : null,
                  child: passengerPhotoUrl?.trim().isNotEmpty == true
                      ? null
                      : const Icon(Icons.person_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    passengerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ],
            ),

            if (routeAdvisory.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: semantic.warningContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 19,
                      color: semantic.onWarningContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        routeAdvisory,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: semantic.onWarningContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            _LocationLine(
              icon: Icons.trip_origin,
              label: 'Pickup',
              address: pickupAddress,
              color: semantic.success,
            ),
            const SizedBox(height: 8),
            _LocationLine(
              icon: Icons.location_on,
              label: 'Destination',
              address: destinationAddress,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                _RequestMetric(
                  icon: Icons.payments_outlined,
                  value: estimatedFare,
                ),
                const SizedBox(width: 8),
                _RequestMetric(icon: Icons.route_outlined, value: distance),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDecline,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Decline'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestMetric extends StatelessWidget {
  const _RequestMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.icon,
    required this.label,
    required this.address,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String address;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: address),
            ],
          ),
        ),
      ),
    ],
  );
}
