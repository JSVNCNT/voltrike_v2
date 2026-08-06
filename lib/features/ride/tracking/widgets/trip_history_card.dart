import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/utils/trip_location_label.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';

/// Compact, non-expanding history row. The entire surface opens trip details.
class TripHistoryCard extends StatelessWidget {
  const TripHistoryCard({
    super.key,
    required this.booking,
    required this.otherPartyLabel,
    required this.onTap,
    this.otherPartyPhotoUrl,
    this.submittedRating,
  });

  final Booking booking;
  final String otherPartyLabel;
  final String? otherPartyPhotoUrl;
  final VoidCallback onTap;
  final int? submittedRating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final semantic = AppSemanticColors.of(context);
    final completed = booking.status == BookingStatus.completed;
    final terminalDate = BookingStateMachine.terminalDate(booking);
    final statusLabel = completed ? 'Completed' : cancellationLabelFor(booking);
    final statusColor = completed ? semantic.success : colors.error;
    final photoUrl = otherPartyPhotoUrl?.trim();

    return Semantics(
      button: true,
      label:
          '$statusLabel trip with $otherPartyLabel, '
          '${tripLocationLabel(booking.pickupName, booking.pickupAddress)} to '
          '${tripLocationLabel(booking.destinationName, booking.destinationAddress)}, '
          '${DateFormat('MMM d, yyyy h:mm a').format(terminalDate)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: colors.primaryContainer,
                      foregroundImage: photoUrl?.isNotEmpty == true
                          ? NetworkImage(photoUrl!)
                          : null,
                      child: photoUrl?.isNotEmpty == true
                          ? null
                          : Icon(
                              Icons.person_outline_rounded,
                              color: colors.onPrimaryContainer,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            otherPartyLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('h:mm a').format(terminalDate),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(label: statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: 16),
                _RouteLine(
                  icon: Icons.trip_origin_rounded,
                  iconColor: colors.primary,
                  address: tripLocationLabel(
                    booking.pickupName,
                    booking.pickupAddress,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Container(
                    width: 2,
                    height: 12,
                    color: colors.outlineVariant,
                  ),
                ),
                _RouteLine(
                  icon: Icons.location_on_rounded,
                  iconColor: colors.secondary,
                  address: tripLocationLabel(
                    booking.destinationName,
                    booking.destinationAddress,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      NumberFormat.currency(
                        locale: 'en_PH',
                        symbol: '₱',
                      ).format(booking.amountDue),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    if (completed && submittedRating != null) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: semantic.rating,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$submittedRating',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String cancellationLabelFor(Booking booking) {
  return switch (booking.cancellationCode) {
    'passenger_no_show' => 'No-show',
    'cancelled_by_passenger' => 'Passenger cancelled',
    'cancelled_by_driver' => 'Driver cancelled',
    _ => 'Cancelled',
  };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.icon,
    required this.iconColor,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
