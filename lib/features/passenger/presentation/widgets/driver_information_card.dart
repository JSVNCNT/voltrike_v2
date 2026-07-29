import 'package:flutter/material.dart';

import '../../../common/presentation/widgets/star_rating.dart';

/// ===========================================================================
/// Driver Information Card
///
/// Displays information about the assigned driver.
///
/// This widget is intentionally presentation-only.
/// Compact ride actions may be placed beside the driver identity.
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
    this.compact = false,
    this.actions,
  });

  final String driverName;
  final String vehicleNumber;
  final String plateNumber;
  final String todaName;
  final String? photoUrl;
  final double? rating;
  final bool compact;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhoto = photoUrl?.trim().isNotEmpty == true;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person_rounded, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              driverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Registered VolTrike driver',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (rating != null && !compact) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            StarRating(rating: rating!, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              rating!.toStringAsFixed(1),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions != null) ...[
                  const SizedBox(width: 8),
                  actions!,
                ] else
                  Icon(
                    Icons.electric_rickshaw_rounded,
                    color: colorScheme.primary,
                  ),
              ],
            ),
            if (compact && rating != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  StarRating(rating: rating!, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    rating!.toStringAsFixed(1),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            if (compact) ...[
              const SizedBox(height: 8),
              Text(
                [
                  vehicleNumber,
                  plateNumber,
                ].where((value) => value.trim().isNotEmpty).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else ...[
              const Divider(height: 28),
              _DriverDetail(
                icon: Icons.electric_rickshaw_outlined,
                label: 'Vehicle',
                value: vehicleNumber,
              ),
              const SizedBox(height: 10),
              _DriverDetail(
                icon: Icons.confirmation_number_outlined,
                label: 'Plate number',
                value: plateNumber,
              ),
              const SizedBox(height: 10),
              _DriverDetail(
                icon: Icons.location_city_outlined,
                label: 'TODA',
                value: todaName,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverDetail extends StatelessWidget {
  const _DriverDetail({
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: colorScheme.onSecondaryContainer),
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
              const SizedBox(height: 1),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
