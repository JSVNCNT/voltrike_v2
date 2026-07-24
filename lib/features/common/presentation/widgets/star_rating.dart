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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        maxRating,
        (index) {
          final star = index + 1;

          IconData icon;

          if (rating >= star) {
            icon = Icons.star;
          } else if (rating >= star - 0.5) {
            icon = Icons.star_half;
          } else {
            icon = Icons.star_border;
          }

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing / 2,
            ),
            child: IconButton(
              onPressed: onRatingChanged == null
                  ? null
                  : () => onRatingChanged!(
                        star.toDouble(),
                      ),
              splashRadius: size * 0.7,
              iconSize: size,
              icon: Icon(
                icon,
                color: color,
              ),
              tooltip:
                  '$star Star${star > 1 ? 's' : ''}',
            ),
          );
        },
      ),
    );
  }
}