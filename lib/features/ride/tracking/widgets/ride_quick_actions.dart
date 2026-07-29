import 'package:flutter/material.dart';

import '../../../../core/theme/app_semantic_colors.dart';

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
    this.buttonSize = 42,
  });

  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final VoidCallback? onReport;
  final VoidCallback? onSos;
  final VoidCallback? onSafetyUpdate;
  final int messageBadge;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final actions = <_QuickAction>[
      if (onCall != null)
        _QuickAction(
          icon: Icons.call_rounded,
          label: 'Call',
          onPressed: onCall!,
          foregroundColor: semantic.onCallAction,
          backgroundColor: semantic.callAction,
        ),
      if (onChat != null)
        _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chat',
          onPressed: onChat!,
          badge: messageBadge,
          foregroundColor: semantic.onChatAction,
          backgroundColor: semantic.chatAction,
        ),
      if (onReport != null)
        _QuickAction(
          icon: Icons.description_outlined,
          label: 'Report',
          onPressed: onReport!,
          foregroundColor: semantic.onReportAction,
          backgroundColor: semantic.reportAction,
        ),
      if (onSos != null && onSafetyUpdate == null)
        _QuickAction(
          icon: Icons.sos_rounded,
          label: 'SOS',
          onPressed: onSos!,
          foregroundColor: colorScheme.onError,
          backgroundColor: colorScheme.error,
        ),
      if (onSafetyUpdate != null)
        _QuickAction(
          icon: Icons.gpp_good_rounded,
          label: 'Update safety status',
          onPressed: onSafetyUpdate!,
          foregroundColor: semantic.onSafetyAction,
          backgroundColor: semantic.safetyAction,
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Ride actions',
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions)
            _QuickAction(
              icon: action.icon,
              label: action.label,
              onPressed: action.onPressed,
              foregroundColor: action.foregroundColor,
              backgroundColor: action.backgroundColor,
              badge: action.badge,
              size: buttonSize < 48 ? 48 : buttonSize,
            ),
        ],
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
    this.size = 42,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final int badge;
  final double size;

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
            IconButton(
              onPressed: onPressed,
              icon: Icon(icon),
              style: IconButton.styleFrom(
                foregroundColor: foregroundColor ?? colorScheme.primary,
                backgroundColor:
                    backgroundColor ?? colorScheme.primaryContainer,
                fixedSize: Size.square(size),
                minimumSize: Size.square(size),
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
