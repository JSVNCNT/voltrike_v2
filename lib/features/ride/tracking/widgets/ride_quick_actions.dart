import 'package:flutter/material.dart';

/// Compact, glanceable actions that stay near the other ride participant.
///
/// Pickup coordination exposes call/chat. Once the trip starts, those actions
/// are replaced by report/SOS so the visible controls match the current stage.
class RideQuickActions extends StatelessWidget {
  const RideQuickActions({
    super.key,
    this.onCall,
    this.onChat,
    this.onReport,
    this.onSos,
    this.onSafetyUpdate,
    this.messageBadge = 0,
  });

  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final VoidCallback? onReport;
  final VoidCallback? onSos;
  final VoidCallback? onSafetyUpdate;
  final int messageBadge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = <_QuickAction>[
      if (onCall != null)
        _QuickAction(
          icon: Icons.call_rounded,
          label: 'Call',
          onPressed: onCall!,
        ),
      if (onChat != null)
        _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chat',
          onPressed: onChat!,
          badge: messageBadge,
        ),
      if (onReport != null)
        _QuickAction(
          icon: Icons.assignment_late_outlined,
          label: 'Report',
          onPressed: onReport!,
          foregroundColor: colorScheme.error,
          backgroundColor: colorScheme.errorContainer,
        ),
      if (onSos != null)
        _QuickAction(
          icon: Icons.sos_rounded,
          label: 'SOS',
          onPressed: onSos!,
          foregroundColor: colorScheme.onError,
          backgroundColor: colorScheme.error,
        ),
      if (onSafetyUpdate != null)
        _QuickAction(
          icon: Icons.health_and_safety_outlined,
          label: 'Update safety status',
          onPressed: onSafetyUpdate!,
          foregroundColor: colorScheme.error,
          backgroundColor: colorScheme.errorContainer,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Ride actions',
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: actions,
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor,
    this.backgroundColor,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              onPressed: onPressed,
              icon: Icon(icon),
              color: foregroundColor ?? colorScheme.primary,
              style: IconButton.styleFrom(
                backgroundColor:
                    backgroundColor ?? colorScheme.primaryContainer,
                minimumSize: const Size.square(48),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -4,
                top: -4,
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onError,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
