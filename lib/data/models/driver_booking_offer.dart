import 'package:cloud_firestore/cloud_firestore.dart';

class DriverBookingOffer {
  const DriverBookingOffer({
    required this.bookingId,
    required this.expiresAt,
  });

  final String bookingId;
  final DateTime expiresAt;

  factory DriverBookingOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return DriverBookingOffer(
      bookingId: data['bookingId'] as String,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
    );
  }

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}
