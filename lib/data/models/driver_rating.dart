import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// ===========================================================================
/// Driver Rating
///
/// Firestore
/// ratings/{ratingId}
///
/// Stores passenger feedback after a completed trip.
/// ===========================================================================
class DriverRating extends Equatable {
  const DriverRating({
    required this.ratingId,
    required this.bookingId,
    required this.driverId,
    required this.passengerId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  //==========================================================================
  // Identity
  //==========================================================================

  final String ratingId;

  final String bookingId;

  final String driverId;

  final String passengerId;

  //==========================================================================
  // Rating
  //==========================================================================

  final int rating;

  final String comment;

  //==========================================================================
  // Dates
  //==========================================================================

  final DateTime createdAt;

  //==========================================================================
  // Firestore
  //==========================================================================

  factory DriverRating.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;

    return DriverRating(
      ratingId: doc.id,
      bookingId:
          data['bookingId'] as String,
      driverId:
          data['driverId'] as String,
      passengerId:
          data['passengerId'] as String,
      rating:
          data['rating'] as int,
      comment:
          data['comment'] as String,
      createdAt:
          (data['createdAt']
                  as Timestamp)
              .toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'bookingId': bookingId,
      'driverId': driverId,
      'passengerId': passengerId,
      'rating': rating,
      'comment': comment,
      'createdAt':
          Timestamp.fromDate(
        createdAt,
      ),
    };
  }

  //==========================================================================
  // Copy
  //==========================================================================

  DriverRating copyWith({
    String? ratingId,
    String? bookingId,
    String? driverId,
    String? passengerId,
    int? rating,
    String? comment,
    DateTime? createdAt,
  }) {
    return DriverRating(
      ratingId:
          ratingId ?? this.ratingId,
      bookingId:
          bookingId ?? this.bookingId,
      driverId:
          driverId ?? this.driverId,
      passengerId:
          passengerId ??
              this.passengerId,
      rating:
          rating ?? this.rating,
      comment:
          comment ?? this.comment,
      createdAt:
          createdAt ??
              this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        ratingId,
        bookingId,
        driverId,
        passengerId,
        rating,
        comment,
        createdAt,
      ];
}