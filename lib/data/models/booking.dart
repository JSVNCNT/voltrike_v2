import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ===========================================================================
/// Booking Status
///
/// Represents the lifecycle of a booking stored in Firestore.
///
/// Flow:
/// pending
/// → driverAssigned
/// → driverArriving
/// → passengerOnBoard
/// → completed
///
/// or
///
/// pending
/// → cancelled
///
/// UI-only states (such as estimating fare or searching for a driver)
/// should not be stored in Firestore.
/// ===========================================================================
enum BookingStatus {
  pending,
  driverAssigned,
  driverArriving,
  passengerOnBoard,
  completed,
  cancelled,
}

/// ===========================================================================
/// Booking Model
///
/// Represents a ride booking stored in Firestore.
///
/// Firestore Collection:
/// bookings/{bookingId}
/// ===========================================================================
class Booking {
  const Booking({
    required this.bookingId,
    required this.passengerId,
    this.driverId,
    required this.pickup,
    required this.destination,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceMeters,
    required this.estimatedFare,
    required this.additionalPassengers,
    required this.baggageCount,
    required this.isOutsideToda,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String bookingId;

  final String passengerId;

  final String? driverId;

  final LatLng pickup;

  final LatLng destination;

  final String pickupAddress;

  final String destinationAddress;

  final int distanceMeters;

  final double estimatedFare;

  final int additionalPassengers;

  final int baggageCount;

  final bool isOutsideToda;

  final BookingStatus status;

  final DateTime createdAt;

  final DateTime updatedAt;

  /// Nullable because old bookings won't have this field.
  final DateTime? completedAt;

  //==========================================================================
  // Firestore
  //==========================================================================

  factory Booking.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;

    return Booking(
      bookingId: doc.id,
      passengerId: data['passengerId'] as String,
      driverId: data['driverId'] as String?,
      pickup: LatLng(
        (data['pickup']['latitude'] as num).toDouble(),
        (data['pickup']['longitude'] as num).toDouble(),
      ),
      destination: LatLng(
        (data['destination']['latitude'] as num).toDouble(),
        (data['destination']['longitude'] as num).toDouble(),
      ),
      pickupAddress: data['pickupAddress'] as String,
      destinationAddress: data['destinationAddress'] as String,
      distanceMeters: data['distanceMeters'] as int,
      estimatedFare: (data['estimatedFare'] as num).toDouble(),
      additionalPassengers: data['additionalPassengers'] as int,
      baggageCount: data['baggageCount'] as int,
      isOutsideToda: data['isOutsideToda'] as bool,
      status: BookingStatus.values.firstWhere(
        (status) => status.name == data['status'],
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'passengerId': passengerId,
      'driverId': driverId,
      'pickup': {
        'latitude': pickup.latitude,
        'longitude': pickup.longitude,
      },
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'distanceMeters': distanceMeters,
      'estimatedFare': estimatedFare,
      'additionalPassengers': additionalPassengers,
      'baggageCount': baggageCount,
      'isOutsideToda': isOutsideToda,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
    };
  }

  //==========================================================================
  // Copy
  //==========================================================================

  Booking copyWith({
    String? bookingId,
    String? passengerId,
    String? driverId,
    LatLng? pickup,
    LatLng? destination,
    String? pickupAddress,
    String? destinationAddress,
    int? distanceMeters,
    double? estimatedFare,
    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,
    BookingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return Booking(
      bookingId: bookingId ?? this.bookingId,
      passengerId: passengerId ?? this.passengerId,
      driverId: driverId ?? this.driverId,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destinationAddress:
          destinationAddress ?? this.destinationAddress,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      estimatedFare: estimatedFare ?? this.estimatedFare,
      additionalPassengers:
          additionalPassengers ?? this.additionalPassengers,
      baggageCount: baggageCount ?? this.baggageCount,
      isOutsideToda: isOutsideToda ?? this.isOutsideToda,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}