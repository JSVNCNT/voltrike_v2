import 'package:flutter/material.dart';

/// ===========================================================================
/// Destination Search Bar
///
/// Displays the destination search field.
///
/// Later this widget will integrate with:
/// • Google Places API (New)
/// • Recent destinations
/// • Favorite places
/// • Saved locations
/// ===========================================================================
class DestinationSearchBar
    extends StatelessWidget {
  const DestinationSearchBar({
    super.key,
    this.hintText = 'Where are you going?',
    this.onTap,
  });

  final String hintText;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      borderRadius:
          BorderRadius.circular(16),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  hintText,
                  style: theme
                      .textTheme.bodyLarge,
                ),
              ),

              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}