import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'model_date_parser.dart';

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
    this.passengerName,
    this.passengerPhone,
    this.passengerPhotoUrl,
    this.driverId,

    //======================================================================
    // Driver Snapshot
    //======================================================================

    this.driverName,
    this.driverPhotoUrl,
    this.driverRating,
    this.vehicleNumber,
    this.plateNumber,
    this.todaName,

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

  //==========================================================================
  // Identity
  //==========================================================================

  final String bookingId;

  final String passengerId;
  final String? passengerName;
  final String? passengerPhone;
  final String? passengerPhotoUrl;

  final String? driverId;

  //==========================================================================
  // Driver Snapshot
  //==========================================================================

  /// Copied when a driver accepts the booking.
  /// This allows passenger screens to display driver
  /// information without extra Firestore queries.

  final String? driverName;

  final String? driverPhotoUrl;

  final double? driverRating;

  final String? vehicleNumber;

  final String? plateNumber;

  final String? todaName;

  //==========================================================================
  // Trip
  //==========================================================================

  final LatLng pickup;

  final LatLng destination;

  final String pickupAddress;

  final String destinationAddress;

  final int distanceMeters;

  final double estimatedFare;

  final int additionalPassengers;

  final int baggageCount;

  final bool isOutsideToda;

  //==========================================================================
  // Status
  //==========================================================================

  final BookingStatus status;

  //==========================================================================
  // Dates
  //==========================================================================

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
      passengerName: data['passengerName'] as String?,
      passengerPhone: data['passengerPhone'] as String?,
      passengerPhotoUrl: data['passengerPhotoUrl'] as String?,
      driverId: data['driverId'] as String?,

      //=========================
      // Driver Snapshot
      //=========================

      driverName: data['driverName'] as String?,
      driverPhotoUrl: data['driverPhotoUrl'] as String?,
      driverRating:
          (data['driverRating'] as num?)?.toDouble(),
      vehicleNumber: data['vehicleNumber'] as String?,
      plateNumber: data['plateNumber'] as String?,
      todaName: data['todaName'] as String?,

      pickup: LatLng(
        (data['pickup']['latitude'] as num).toDouble(),
        (data['pickup']['longitude'] as num).toDouble(),
      ),
      destination: LatLng(
        (data['destination']['latitude'] as num).toDouble(),
        (data['destination']['longitude'] as num).toDouble(),
      ),
      pickupAddress: data['pickupAddress'] as String,
      destinationAddress:
          data['destinationAddress'] as String,
      distanceMeters: (data['distanceMeters'] as num).toInt(),
      estimatedFare:
          (data['estimatedFare'] as num).toDouble(),
      additionalPassengers:
          data['additionalPassengers'] as int,
      baggageCount: (data['baggageCount'] as num).toInt(),
      isOutsideToda: data['isOutsideToda'] as bool,
      status: BookingStatus.values.firstWhere(
        (status) => status.name == data['status'],
      ),
      createdAt: parseModelDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: parseModelDate(data['updatedAt']) ?? DateTime.now(),
      completedAt: parseModelDate(data['completedAt']),
    );
  }

    Map<String, dynamic> toFirestore() {
    return {
      //======================================================================
      // Identity
      //======================================================================

      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerPhotoUrl': passengerPhotoUrl,
      'driverId': driverId,

      //======================================================================
      // Driver Snapshot
      //======================================================================

      'driverName': driverName,
      'driverPhotoUrl': driverPhotoUrl,
      'driverRating': driverRating,
      'vehicleNumber': vehicleNumber,
      'plateNumber': plateNumber,
      'todaName': todaName,

      //======================================================================
      // Trip
      //======================================================================

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

      //======================================================================
      // Status
      //======================================================================

      'status': status.name,

      //======================================================================
      // Dates
      //======================================================================

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
    String? passengerName,
    String? passengerPhone,
    String? passengerPhotoUrl,
    String? driverId,

    //======================================================================
    // Driver Snapshot
    //======================================================================

    String? driverName,
    String? driverPhotoUrl,
    double? driverRating,
    String? vehicleNumber,
    String? plateNumber,
    String? todaName,

    //======================================================================
    // Trip
    //======================================================================

    LatLng? pickup,
    LatLng? destination,
    String? pickupAddress,
    String? destinationAddress,
    int? distanceMeters,
    double? estimatedFare,
    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,

    //======================================================================
    // Status
    //======================================================================

    BookingStatus? status,

    //======================================================================
    // Dates
    //======================================================================

    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return Booking(
      bookingId: bookingId ?? this.bookingId,
      passengerId: passengerId ?? this.passengerId,
      passengerName: passengerName ?? this.passengerName,
      passengerPhone: passengerPhone ?? this.passengerPhone,
      passengerPhotoUrl: passengerPhotoUrl ?? this.passengerPhotoUrl,
      driverId: driverId ?? this.driverId,

      //====================================================================
      // Driver Snapshot
      //====================================================================

      driverName: driverName ?? this.driverName,
      driverPhotoUrl:
          driverPhotoUrl ?? this.driverPhotoUrl,
      driverRating:
          driverRating ?? this.driverRating,
      vehicleNumber:
          vehicleNumber ?? this.vehicleNumber,
      plateNumber:
          plateNumber ?? this.plateNumber,
      todaName: todaName ?? this.todaName,

      //====================================================================
      // Trip
      //====================================================================

      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      pickupAddress:
          pickupAddress ?? this.pickupAddress,
      destinationAddress:
          destinationAddress ??
              this.destinationAddress,
      distanceMeters:
          distanceMeters ?? this.distanceMeters,
      estimatedFare:
          estimatedFare ?? this.estimatedFare,
      additionalPassengers:
          additionalPassengers ??
              this.additionalPassengers,
      baggageCount:
          baggageCount ?? this.baggageCount,
      isOutsideToda:
          isOutsideToda ?? this.isOutsideToda,

      //====================================================================
      // Status
      //====================================================================

      status: status ?? this.status,

      //====================================================================
      // Dates
      //====================================================================

      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
