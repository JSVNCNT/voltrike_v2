import 'package:flutter/material.dart';

import '../../../../data/models/booking.dart';

/// Compact, shared progress treatment for passenger and driver multi-stop
/// tracking. The booking state remains authoritative; this widget only makes
/// the current and final legs easier to understand at a glance.
class MultiStopProgressCard extends StatelessWidget {
  const MultiStopProgressCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final stops = booking.dropoffStops;
    if (stops.length < 2) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final completedCount = stops
        .where((stop) => stop.status == 'completed')
        .length
        .clamp(0, stops.length);
    final isOnTrip = booking.status == BookingStatus.passengerOnBoard;
    final finalReached =
        booking.status == BookingStatus.paymentConfirmation ||
        booking.status == BookingStatus.completed;
    final currentIndex = finalReached
        ? stops.length - 1
        : isOnTrip
        ? completedCount.clamp(0, stops.length - 1)
        : 0;
    final currentStop = stops[currentIndex];
    final currentName = currentStop.name.trim().isNotEmpty
        ? currentStop.name.trim()
        : currentStop.address.trim();

    final title = finalReached
        ? 'Final drop-off reached'
        : isOnTrip
        ? 'Drop-off ${currentIndex + 1} of ${stops.length}'
        : '${stops.length}-drop-off trip';
    final destinationText = finalReached
        ? 'Final stop: $currentName'
        : isOnTrip
        ? 'Now heading to $currentName'
        : 'First: ${_stopName(stops.first)}  •  Final: ${_stopName(stops.last)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline, width: 1.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  '${stops.length} stops',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var index = 0; index < stops.length; index++) ...[
                _StopNode(
                  number: index + 1,
                  completed: index < completedCount || finalReached,
                  active: index == currentIndex && !finalReached,
                ),
                if (index < stops.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index < completedCount
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            destinationText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: isOnTrip ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  static String _stopName(BookingRouteStop stop) {
    return stop.name.trim().isNotEmpty ? stop.name.trim() : stop.address.trim();
  }
}

class _StopNode extends StatelessWidget {
  const _StopNode({
    required this.number,
    required this.completed,
    required this.active,
  });

  final int number;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = completed || active
        ? colorScheme.primary
        : colorScheme.surface;
    final foreground = completed || active
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: completed
          ? Icon(Icons.check_rounded, size: 17, color: foreground)
          : Text(
              '$number',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
