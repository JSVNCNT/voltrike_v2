import 'package:flutter/material.dart';

/// ===========================================================================
/// Ride Actions Card
///
/// Shared actions available during an active ride.
///
/// Used by:
/// • Passenger BookingTrackingScreen
/// • Driver BookingTrackingScreen
/// ===========================================================================
class RideActionsCard extends StatelessWidget {
  const RideActionsCard({
    super.key,
    this.onCall,
    this.onMessage,
    this.onReport,
    this.onCancel,
    this.onSos,
    this.onNoShow,
    this.messageBadge = 0,
  });

  final VoidCallback? onCall;
  final VoidCallback? onMessage;
  final VoidCallback? onReport;
  final VoidCallback? onCancel;
  final VoidCallback? onSos;
  final VoidCallback? onNoShow;
  final int messageBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final actions = <_ActionButton>[
      if (onCall != null)
        _ActionButton(icon: Icons.call, label: 'Call', onPressed: onCall!),
      if (onMessage != null)
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          label: 'Message',
          onPressed: onMessage!,
          badge: messageBadge,
        ),
      if (onReport != null)
        _ActionButton(
          icon: Icons.report_problem_outlined,
          label: 'Report',
          foregroundColor: theme.colorScheme.error,
          onPressed: onReport!,
        ),
      if (onSos != null)
        _ActionButton(
          icon: Icons.sos,
          label: 'SOS',
          foregroundColor: theme.colorScheme.error,
          onPressed: onSos!,
        ),
      if (onCancel != null)
        _ActionButton(
          icon: Icons.cancel_outlined,
          label: 'Cancel',
          foregroundColor: theme.colorScheme.error,
          onPressed: onCancel!,
        ),
      if (onNoShow != null)
        _ActionButton(
          icon: Icons.person_off_outlined,
          label: 'No-show',
          foregroundColor: theme.colorScheme.error,
          onPressed: onNoShow!,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final action in actions) action],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            minimumSize: const Size(0, 44),
          ),
        ),
        if (badge > 0)
          Positioned(top: -7, right: -7, child: _UnreadBadge(count: badge)),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onError,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
