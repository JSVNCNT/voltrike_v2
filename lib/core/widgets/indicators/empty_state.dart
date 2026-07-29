import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.button,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? button;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                icon,
                size: 52,
                color: colorScheme.onPrimaryContainer,
              ),
            ),

            const SizedBox(height: 24),

            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            if (button != null) ...[const SizedBox(height: 28), button!],
          ],
        ),
      ),
    );
  }
}
