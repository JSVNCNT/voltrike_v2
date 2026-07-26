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
    this.distanceMeters,
  });

  final String placeId;

  final String title;

  final String? subtitle;

  /// Dynamic proximity from the active GPS/search origin.
  final int? distanceMeters;

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      placeId: json['placeId'] as String,
      title: json['text'] as String,
      subtitle: json['secondaryText'] as String?,
      distanceMeters: (json['distanceMeters'] as num?)?.round(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'text': title,
      'secondaryText': subtitle,
      'distanceMeters': distanceMeters,
    };
  }

  PlacePrediction copyWith({
    String? placeId,
    String? title,
    String? subtitle,
    int? distanceMeters,
  }) {
    return PlacePrediction(
      placeId: placeId ?? this.placeId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }

  @override
  String toString() {
    return 'PlacePrediction('
        'placeId: $placeId, '
        'title: $title, '
        'subtitle: $subtitle, '
        'distanceMeters: $distanceMeters'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return other is PlacePrediction &&
        other.placeId == placeId &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.distanceMeters == distanceMeters;
  }

  @override
  int get hashCode => Object.hash(placeId, title, subtitle, distanceMeters);
}
