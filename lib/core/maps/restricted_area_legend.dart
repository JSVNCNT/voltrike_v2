import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared map legend for developer-configured restricted operating areas.
///
/// Map views only show this when the live restrictions feed contains at least
/// one active restriction, so the warning always corresponds to visible map
/// geometry rather than being a decorative status label.
class RestrictedAreaLegend extends StatelessWidget {
  const RestrictedAreaLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outline, width: 1.25),
      ),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.restrictedAreaFill,
                  border: Border.fromBorderSide(
                    BorderSide(color: AppColors.restrictedAreaBorder, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('Restricted area', style: TextStyle(color: colors.onSurface)),
          ],
        ),
      ),
    );
  }
}
