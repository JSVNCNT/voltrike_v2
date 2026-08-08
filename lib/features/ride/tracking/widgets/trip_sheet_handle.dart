import 'package:flutter/material.dart';

/// A visible and accessible expand/collapse control for an active-trip sheet.
/// The centred grip remains a familiar drag affordance; the button makes the
/// same action discoverable without requiring a drag gesture.
class TripSheetHandle extends StatelessWidget {
  const TripSheetHandle({
    super.key,
    required this.isExpanded,
    required this.onPressed,
    this.expandLabel = 'Show trip details',
    this.collapseLabel = 'Hide trip details',
  });

  final bool isExpanded;
  final VoidCallback onPressed;
  final String expandLabel;
  final String collapseLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.black.withValues(alpha: 0.78);
    final label = isExpanded ? collapseLabel : expandLabel;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Positioned(
            right: 4,
            child: Semantics(
              button: true,
              label: label,
              child: IconButton(
                onPressed: onPressed,
                tooltip: label,
                icon: Icon(
                  isExpanded
                      ? Icons.unfold_less_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
