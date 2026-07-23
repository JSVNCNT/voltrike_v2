import 'package:flutter/material.dart';

/// ===========================================================================
/// Location Permission Card
///
/// Displayed when location permission has not been granted.
///
/// Used by:
/// • Passenger Home
/// • Driver Home
/// • Booking
/// • Navigation
/// ===========================================================================
class LocationPermissionCard extends StatelessWidget {
  const LocationPermissionCard({
    super.key,
    this.title = 'Location Permission Required',
    this.message =
        'VolTrike needs access to your location to provide accurate pickup, navigation, and trip tracking.',
    this.onGrantPermission,
    this.onOpenSettings,
  });

  final String title;

  final String message;

  final VoidCallback? onGrantPermission;

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 64,
              color: theme.colorScheme.error,
            ),

            const SizedBox(height: 20),

            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            if (onGrantPermission != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onGrantPermission,
                  icon: const Icon(Icons.my_location),
                  label: const Text(
                    'Grant Permission',
                  ),
                ),
              ),

            if (onOpenSettings != null) ...[
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text(
                    'Open Settings',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}