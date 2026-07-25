import 'package:flutter/material.dart';

class RideSecondaryActions extends StatelessWidget {
  const RideSecondaryActions({
    super.key,
    this.onCall,
    this.onChat,
    this.onReport,
    this.onCancel,
  });

  final VoidCallback? onCall;
  final VoidCallback? onChat;
  final VoidCallback? onReport;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onCall != null)
        _RideActionButton(
          icon: Icons.call,
          label: 'Call',
          onPressed: onCall!,
        ),
      if (onChat != null)
        _RideActionButton(
          icon: Icons.chat,
          label: 'Chat',
          onPressed: onChat!,
        ),
      if (onReport != null)
        _RideActionButton(
          icon: Icons.report,
          label: 'Report',
          onPressed: onReport!,
        ),
      if (onCancel != null)
        _RideActionButton(
          icon: Icons.cancel,
          label: 'Cancel',
          onPressed: onCancel!,
        ),
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: actions,
    );
  }
}

class _RideActionButton extends StatelessWidget {
  const _RideActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}