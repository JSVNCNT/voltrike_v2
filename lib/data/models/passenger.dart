import 'package:equatable/equatable.dart';
import 'model_date_parser.dart';

class Passenger extends Equatable {
  const Passenger({
    required this.uid,
    required this.favoriteLocations,
    required this.totalTrips,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Same as the Firebase Authentication UID.
  final String uid;

  /// User's saved pickup/drop-off locations.
  final List<String> favoriteLocations;

  /// Number of completed trips.
  final int totalTrips;

  /// Average passenger rating.
  final double rating;

  /// Timestamp when the passenger profile was created.
  final DateTime createdAt;

  /// Timestamp when the passenger profile was last updated.
  final DateTime updatedAt;

  Passenger copyWith({
    String? uid,
    List<String>? favoriteLocations,
    int? totalTrips,
    double? rating,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Passenger(
      uid: uid ?? this.uid,
      favoriteLocations:
          favoriteLocations ?? this.favoriteLocations,
      totalTrips: totalTrips ?? this.totalTrips,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Passenger.fromMap(
    Map<String, dynamic> map,
  ) {
    return Passenger(
      uid: map['uid'] ?? '',
      favoriteLocations: List<String>.from(
        map['favoriteLocations'] ?? const [],
      ),
      totalTrips: map['totalTrips'] ?? 0,
      rating: (map['rating'] ?? 0).toDouble(),
      createdAt: parseModelDate(map['createdAt']) ??
          DateTime.now(),
      updatedAt: parseModelDate(map['updatedAt']) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'favoriteLocations': favoriteLocations,
      'totalTrips': totalTrips,
      'rating': rating,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        uid,
        favoriteLocations,
        totalTrips,
        rating,
        createdAt,
        updatedAt,
      ];
}
