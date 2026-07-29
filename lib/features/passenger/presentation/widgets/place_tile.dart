import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/utils/distance_formatter.dart';

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
    this.distanceMeters,
    this.isRecommended = false,
    this.onTap,
    this.icon = Icons.location_on_outlined,
  });

  /// Main place name.
  final String title;

  /// Secondary address text.
  final String subtitle;

  final int? distanceMeters;

  final bool isRecommended;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final semantic = AppSemanticColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isRecommended ? colors.primary : colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                icon,
                color: isRecommended
                    ? colors.onPrimary
                    : colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (isRecommended) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.near_me, size: 15, color: semantic.success),
                        const SizedBox(width: 4),
                        Text(
                          'Recommended · Nearest',
                          style: TextStyle(
                            color: semantic.success,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (distanceMeters != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Text(
                  DistanceFormatter.compactMeters(distanceMeters!),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
