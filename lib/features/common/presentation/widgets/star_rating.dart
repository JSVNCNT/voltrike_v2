import 'package:flutter/material.dart';

/// ===========================================================================
/// Star Rating
///
/// Interactive:
/// ```dart
/// StarRating(
///   rating: 5,
///   onRatingChanged: (rating) {
///     setState(() {
///       _rating = rating.round();
///     });
///   },
/// )
/// ```
///
/// Read-only:
/// ```dart
/// StarRating(
///   rating: 4.6,
/// )
/// ```
/// ===========================================================================
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.onRatingChanged,
    this.maxRating = 5,
    this.size = 40,
    this.color = Colors.amber,
    this.spacing = 4,
  });

  /// Current rating.
  ///
  /// Supports decimal values (e.g. 4.3, 4.8).
  final double rating;

  /// If null, the widget is read-only.
  final ValueChanged<double>? onRatingChanged;

  /// Maximum number of stars.
  final int maxRating;

  /// Star size.
  final double size;

  /// Star color.
  final Color color;

  /// Space between stars.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (onRatingChanged == null) {
      return Semantics(
        label: 'Rating ${rating.toStringAsFixed(1)} out of $maxRating',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              maxRating,
              (index) => Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                child: Icon(
                  _iconFor(index + 1),
                  size: size,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        maxRating,
        (index) {
          final star = index + 1;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing / 2,
            ),
            child: Semantics(
              button: true,
              selected: rating.round() == star,
              label: '$star out of $maxRating stars',
              child: IconButton(
                onPressed: () => onRatingChanged!(star.toDouble()),
                splashRadius: size * 0.7,
                iconSize: size,
                icon: ExcludeSemantics(
                  child: Icon(
                    _iconFor(star),
                    color: color,
                  ),
                ),
                tooltip: '$star Star${star > 1 ? 's' : ''}',
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(int star) {
    if (rating >= star) return Icons.star;
    if (rating >= star - 0.5) return Icons.star_half;
    return Icons.star_border;
  }
}
