import 'package:flutter/material.dart';

/// ===========================================================================
/// Network Error Widget
///
/// Reusable widget displayed when a network request fails.
///
/// Used by:
/// • Firestore
/// • Google Maps
/// • Routes API
/// • Places API
/// • Driver Search
/// • Booking Requests
/// ===========================================================================
class NetworkErrorWidget extends StatelessWidget {
  const NetworkErrorWidget({
    super.key,
    this.title = 'Connection Error',
    this.message =
        'Unable to connect. Please check your internet connection and try again.',
    this.onRetry,
  });

  final String title;

  final String message;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 72,
              color: theme.colorScheme.error,
            ),

            const SizedBox(height: 24),

            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),

            if (onRetry != null) ...[
              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}