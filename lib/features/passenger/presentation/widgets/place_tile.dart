import 'package:flutter/material.dart';

/// ===========================================================================
/// Place Tile
///
/// Displays a destination returned by the Google Places API.
///
/// Used by:
/// • DestinationSearchScreen
/// ===========================================================================
class PlaceTile extends StatelessWidget {
  const PlaceTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;

  final String subtitle;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(
          Icons.location_on_outlined,
        ),
      ),
      title: Text(title),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle),
      trailing: const Icon(
        Icons.chevron_right,
      ),
      onTap: onTap,
    );
  }
}