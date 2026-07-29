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
    this.onSafetyUpdate,
    this.onNoShow,
    this.messageBadge = 0,
  });

  final VoidCallback? onCall;
  final VoidCallback? onMessage;
  final VoidCallback? onReport;
  final VoidCallback? onCancel;
  final VoidCallback? onSos;
  final VoidCallback? onSafetyUpdate;
  final VoidCallback? onNoShow;
  final int messageBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final actions = <_ActionButton>[
      if (onCall != null)
        _ActionButton(
          icon: Icons.call_rounded,
          label: 'Call',
          onPressed: onCall!,
          emphasis: _ActionEmphasis.tonal,
        ),
      if (onMessage != null)
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chat',
          onPressed: onMessage!,
          badge: messageBadge,
          emphasis: _ActionEmphasis.tonal,
        ),
      if (onReport != null)
        _ActionButton(
          icon: Icons.assignment_late_outlined,
          label: 'Report',
          foregroundColor: theme.colorScheme.error,
          onPressed: onReport!,
        ),
      if (onSos != null)
        _ActionButton(
          icon: Icons.sos_rounded,
          label: 'SOS',
          foregroundColor: theme.colorScheme.error,
          emphasis: _ActionEmphasis.errorTonal,
          onPressed: onSos!,
        ),
      if (onSafetyUpdate != null)
        _ActionButton(
          icon: Icons.health_and_safety_outlined,
          label: 'Safety status',
          foregroundColor: theme.colorScheme.error,
          emphasis: _ActionEmphasis.outlined,
          onPressed: onSafetyUpdate!,
        ),
      if (onCancel != null)
        _ActionButton(
          icon: Icons.close_rounded,
          label: 'Cancel ride',
          foregroundColor: theme.colorScheme.error,
          onPressed: onCancel!,
          emphasis: _ActionEmphasis.text,
        ),
      if (onNoShow != null)
        _ActionButton(
          icon: Icons.person_off_outlined,
          label: 'No-show',
          foregroundColor: theme.colorScheme.error,
          onPressed: onNoShow!,
          emphasis: _ActionEmphasis.text,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final itemWidth = actions.length == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final action in actions)
                  SizedBox(width: itemWidth, child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ActionEmphasis { outlined, tonal, errorTonal, text }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    this.emphasis = _ActionEmphasis.outlined,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final _ActionEmphasis emphasis;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = switch (emphasis) {
      _ActionEmphasis.tonal => FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
      _ActionEmphasis.errorTonal => FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          foregroundColor: theme.colorScheme.onErrorContainer,
          backgroundColor: theme.colorScheme.errorContainer,
        ),
      ),
      _ActionEmphasis.text => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: TextButton.styleFrom(foregroundColor: foregroundColor),
      ),
      _ActionEmphasis.outlined => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: foregroundColor),
      ),
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(width: double.infinity, height: 48, child: button),
        if (badge > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Semantics(
              label: '$badge unread chat messages',
              child: ExcludeSemantics(child: _UnreadBadge(count: badge)),
            ),
          ),
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
