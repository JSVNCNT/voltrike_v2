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
    this.trailing,
  });

  /// Selected location or placeholder.
  final String hintText;

  /// Called when the search bar is tapped.
  final VoidCallback? onTap;

  /// Leading icon.
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fieldColor = theme.brightness == Brightness.dark
        ? const Color(0xFF293536)
        : const Color(0xFFE8ECEC);

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),

              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
