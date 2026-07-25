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
  });

  final VoidCallback? onCall;
  final VoidCallback? onMessage;
  final VoidCallback? onReport;
  final VoidCallback? onCancel;

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
        ),
      if (onReport != null)
        _ActionButton(
          icon: Icons.report_problem_outlined,
          label: 'Report',
          foregroundColor: theme.colorScheme.error,
          onPressed: onReport!,
        ),
      if (onCancel != null)
        _ActionButton(
          icon: Icons.cancel_outlined,
          label: 'Cancel',
          foregroundColor: theme.colorScheme.error,
          onPressed: onCancel!,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions) action,
          ],
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}
