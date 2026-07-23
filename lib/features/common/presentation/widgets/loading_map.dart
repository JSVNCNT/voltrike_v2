import 'package:flutter/material.dart';

/// ===========================================================================
/// Loading Map
///
/// Reusable loading widget displayed while:
///
/// • Google Maps initializes
/// • GPS location is acquired
/// • Route is calculated
/// • Nearby drivers are loading
/// ===========================================================================
class LoadingMap extends StatelessWidget {
  const LoadingMap({
    super.key,
    this.message = 'Loading map...',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),

            const SizedBox(height: 24),

            Text(
              message,
              style: theme.textTheme.titleMedium,
            ),

            const SizedBox(height: 8),

            Text(
              'Please wait...',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}