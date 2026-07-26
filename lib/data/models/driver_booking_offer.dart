import 'package:cloud_firestore/cloud_firestore.dart';

class DriverBookingOffer {
  const DriverBookingOffer({
    required this.bookingId,
    required this.expiresAt,
    this.distanceMeters = 0,
  });

  final String bookingId;
  final DateTime expiresAt;
  final int distanceMeters;

  factory DriverBookingOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return DriverBookingOffer(
      bookingId: data['bookingId'] as String,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      distanceMeters: (data['distanceMeters'] as num?)?.round() ?? 0,
    );
  }

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}
