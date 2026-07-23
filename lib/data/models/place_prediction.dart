/// ===========================================================================
/// Place Prediction
///
/// Represents a destination returned by the Google Places API.
///
/// Used by:
/// • PlacesService
/// • PlacesSearchProvider
/// • DestinationSearchScreen
/// ===========================================================================
class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.title,
    this.subtitle,
  });

  final String placeId;

  final String title;

  final String? subtitle;

  factory PlacePrediction.fromJson(
    Map<String, dynamic> json,
  ) {
    return PlacePrediction(
      placeId: json['placeId'] as String,
      title: json['text'] as String,
      subtitle: json['secondaryText'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'text': title,
      'secondaryText': subtitle,
    };
  }

  PlacePrediction copyWith({
    String? placeId,
    String? title,
    String? subtitle,
  }) {
    return PlacePrediction(
      placeId: placeId ?? this.placeId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  @override
  String toString() {
    return 'PlacePrediction('
        'placeId: $placeId, '
        'title: $title, '
        'subtitle: $subtitle'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return other is PlacePrediction &&
        other.placeId == placeId &&
        other.title == title &&
        other.subtitle == subtitle;
  }

  @override
  int get hashCode =>
      Object.hash(
        placeId,
        title,
        subtitle,
      );
}