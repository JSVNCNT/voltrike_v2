import 'package:flutter/material.dart';

/// ===========================================================================
/// Recent Place Tile
///
/// Displays recently used or favorite places.
///
/// Future:
/// • Home
/// • Work
/// • Recent destinations
/// ===========================================================================
class RecentPlaceTile
    extends StatelessWidget {
  const RecentPlaceTile({
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
          Icons.history,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}