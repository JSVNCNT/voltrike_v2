import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';

enum AppCardAccentEdge { top, leading }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.symmetric(vertical: 8),
    this.onTap,
    this.accentColor,
    this.accentEdge = AppCardAccentEdge.top,
    this.tintColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? accentColor;
  final AppCardAccentEdge accentEdge;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = Theme.of(context).cardTheme.color ?? colors.surface;
    final cardColor = tintColor == null
        ? baseColor
        : Color.alphaBlend(
            tintColor!.withValues(alpha: isDark ? 0.07 : 0.035),
            baseColor,
          );
    final content = Padding(padding: padding, child: child);
    final interactiveContent = onTap == null
        ? content
        : InkWell(onTap: onTap, child: content);
    final card = Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.outline),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          interactiveContent,
          if (accentColor != null)
            Positioned(
              top: 0,
              left: 0,
              right: accentEdge == AppCardAccentEdge.top ? 0 : null,
              bottom: accentEdge == AppCardAccentEdge.leading ? 0 : null,
              width: accentEdge == AppCardAccentEdge.leading ? 4 : null,
              height: accentEdge == AppCardAccentEdge.top ? 4 : null,
              child: IgnorePointer(child: ColoredBox(color: accentColor!)),
            ),
        ],
      ),
    );

    return card;
  }
}
