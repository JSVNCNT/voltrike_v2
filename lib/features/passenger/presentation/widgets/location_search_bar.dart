import 'package:flutter/material.dart';

/// ===========================================================================
/// Location Search Bar
///
/// Reusable search bar for selecting:
/// • Pickup location
/// • Destination
/// ===========================================================================
class LocationSearchBar extends StatelessWidget {
  const LocationSearchBar({
    super.key,
    required this.hintText,
    this.onTap,
    this.icon = Icons.location_on_outlined,
  });

  /// Selected location or placeholder.
  final String hintText;

  /// Called when the search bar is tapped.
  final VoidCallback? onTap;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ),

              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}