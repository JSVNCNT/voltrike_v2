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
    required this.onCall,
    required this.onMessage,
    required this.onReport,
  });

  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.call,
                label: 'Call',
                onPressed: onCall,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _ActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'Message',
                onPressed: onMessage,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _ActionButton(
                icon: Icons.report_problem_outlined,
                label: 'Report',
                foregroundColor: theme.colorScheme.error,
                onPressed: onReport,
              ),
            ),
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