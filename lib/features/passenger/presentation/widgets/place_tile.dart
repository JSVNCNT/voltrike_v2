import 'package:flutter/material.dart';

/// ===========================================================================
/// Place Tile
///
/// Displays a location returned by Google Places.
///
/// Used by:
/// • DestinationSearchScreen (Pickup)
/// • DestinationSearchScreen (Destination)
/// • Recent Places (future)
/// • Favorite Places (future)
/// ===========================================================================
class PlaceTile extends StatelessWidget {
  const PlaceTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.icon = Icons.location_on_outlined,
  });

  /// Main place name.
  final String title;

  /// Secondary address text.
  final String subtitle;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            theme.colorScheme.primaryContainer,
        child: Icon(
          icon,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(
        Icons.chevron_right,
      ),
      onTap: onTap,
    );
  }
}