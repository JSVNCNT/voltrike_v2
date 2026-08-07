import 'package:flutter/material.dart';

/// Keeps a participant's full name visible without making ordinary names look
/// undersized. The text first scales down within a readable range and only
/// grows beyond two lines when the full name still cannot fit.
class AdaptiveParticipantName extends StatelessWidget {
  const AdaptiveParticipantName({
    super.key,
    required this.name,
    required this.style,
    this.preferredMaxLines = 2,
    this.minimumFontSize = 12,
    this.textAlign,
  });

  final String name;
  final TextStyle style;
  final int preferredMaxLines;
  final double minimumFontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final startingFontSize = style.fontSize ?? 16;
        final smallestFontSize = minimumFontSize
            .clamp(1, startingFontSize)
            .toDouble();
        var fontSize = startingFontSize;
        var fitsPreferredLines = false;

        while (fontSize >= smallestFontSize) {
          final painter = TextPainter(
            text: TextSpan(
              text: name,
              style: style.copyWith(fontSize: fontSize),
            ),
            maxLines: preferredMaxLines,
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: constraints.maxWidth);

          if (!painter.didExceedMaxLines) {
            fitsPreferredLines = true;
            break;
          }
          fontSize -= 0.5;
        }

        final resolvedFontSize = fontSize
            .clamp(smallestFontSize, startingFontSize)
            .toDouble();

        return Text(
          name,
          maxLines: fitsPreferredLines ? preferredMaxLines : null,
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: textAlign,
          style: style.copyWith(fontSize: resolvedFontSize),
        );
      },
    );
  }
}
