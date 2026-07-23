import 'package:equatable/equatable.dart';

class Driver extends Equatable {
  const Driver({
    //======================================================================
    // Identity
    //======================================================================

    required this.uid,
    required this.todaId,
    required this.vehicleId,

    //======================================================================
    // License
    //======================================================================

    required this.licenseNumber,
    required this.licenseExpiry,

    //======================================================================
    // Uploaded Documents
    //======================================================================

    required this.profilePhotoUrl,
    required this.driverLicenseFrontUrl,
    required this.driverLicenseBackUrl,
    required this.governmentIdUrl,
    required this.orDocumentUrl,
    required this.crDocumentUrl,
    required this.vehiclePhotoUrl,

    //======================================================================
    // Driver Status
    //======================================================================

    required this.driverStatus,
    required this.isOnline,
    required this.isAvailable,

    this.currentBookingId,
    this.currentLatitude,
    this.currentLongitude,

    //======================================================================
    // Statistics
    //======================================================================

    required this.rating,
    required this.completedTrips,
    required this.totalEarnings,

    //======================================================================
    // Dates
    //======================================================================

    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
  });

  //==========================================================================
  // Identity
  //==========================================================================

  final String uid;

  final String todaId;

  final String vehicleId;

  //==========================================================================
  // License
  //==========================================================================

  final String licenseNumber;

  final DateTime licenseExpiry;

  //==========================================================================
  // Uploaded Documents
  //==========================================================================

  final String profilePhotoUrl;

  final String driverLicenseFrontUrl;

  final String driverLicenseBackUrl;

  final String governmentIdUrl;

  final String orDocumentUrl;

  final String crDocumentUrl;

  final String vehiclePhotoUrl;

  //==========================================================================
  // Driver Status
  //==========================================================================

  /// pending | approved | rejected | suspended
  final String driverStatus;

  /// Driver has toggled Online.
  final bool isOnline;

  /// Driver is available to receive bookings.
  final bool isAvailable;

  /// Active booking.
  final String? currentBookingId;

  /// Live GPS latitude.
  final double? currentLatitude;

  /// Live GPS longitude.
  final double? currentLongitude;

  //==========================================================================
  // Driver Statistics
  //==========================================================================

  final double rating;

  final int completedTrips;

  final double totalEarnings;

  //==========================================================================
  // Dates
  //==========================================================================

  final DateTime createdAt;

  final DateTime? approvedAt;

  final String? approvedBy;

  //==========================================================================
  // Helpers
  //==========================================================================

  bool get isApproved =>
      driverStatus == 'approved';

  bool get isPending =>
      driverStatus == 'pending';

  bool get isRejected =>
      driverStatus == 'rejected';

  bool get isSuspended =>
      driverStatus == 'suspended';

  bool get canReceiveBookings =>
      isApproved &&
      isOnline &&
      isAvailable;

  //==========================================================================
  // Copy
  //==========================================================================
    Driver copyWith({
    //======================================================================
    // Identity
    //======================================================================

    String? uid,
    String? todaId,
    String? vehicleId,

    //======================================================================
    // License
    //======================================================================

    String? licenseNumber,
    DateTime? licenseExpiry,

    //======================================================================
    // Uploaded Documents
    //======================================================================

    String? profilePhotoUrl,
    String? driverLicenseFrontUrl,
    String? driverLicenseBackUrl,
    String? governmentIdUrl,
    String? orDocumentUrl,
    String? crDocumentUrl,
    String? vehiclePhotoUrl,

    //======================================================================
    // Driver Status
    //======================================================================

    String? driverStatus,
    bool? isOnline,
    bool? isAvailable,

    String? currentBookingId,
    double? currentLatitude,
    double? currentLongitude,

    //======================================================================
    // Statistics
    //======================================================================

    double? rating,
    int? completedTrips,
    double? totalEarnings,

    //======================================================================
    // Dates
    //======================================================================

    DateTime? createdAt,
    DateTime? approvedAt,
    String? approvedBy,
  }) {
    return Driver(
      //====================================================================
      // Identity
      //====================================================================

      uid: uid ?? this.uid,
      todaId: todaId ?? this.todaId,
      vehicleId: vehicleId ?? this.vehicleId,

      //====================================================================
      // License
      //====================================================================

      licenseNumber:
          licenseNumber ??
              this.licenseNumber,

      licenseExpiry:
          licenseExpiry ??
              this.licenseExpiry,

      //====================================================================
      // Uploaded Documents
      //====================================================================

      profilePhotoUrl:
          profilePhotoUrl ??
              this.profilePhotoUrl,

      driverLicenseFrontUrl:
          driverLicenseFrontUrl ??
              this.driverLicenseFrontUrl,

      driverLicenseBackUrl:
          driverLicenseBackUrl ??
              this.driverLicenseBackUrl,

      governmentIdUrl:
          governmentIdUrl ??
              this.governmentIdUrl,

      orDocumentUrl:
          orDocumentUrl ??
              this.orDocumentUrl,

      crDocumentUrl:
          crDocumentUrl ??
              this.crDocumentUrl,

      vehiclePhotoUrl:
          vehiclePhotoUrl ??
              this.vehiclePhotoUrl,

      //====================================================================
      // Driver Status
      //====================================================================

      driverStatus:
          driverStatus ??
              this.driverStatus,

      isOnline:
          isOnline ??
              this.isOnline,

      isAvailable:
          isAvailable ??
              this.isAvailable,

      currentBookingId:
          currentBookingId ??
              this.currentBookingId,

      currentLatitude:
          currentLatitude ??
              this.currentLatitude,

      currentLongitude:
          currentLongitude ??
              this.currentLongitude,

      //====================================================================
      // Statistics
      //====================================================================

      rating:
          rating ?? this.rating,

      completedTrips:
          completedTrips ??
              this.completedTrips,

      totalEarnings:
          totalEarnings ??
              this.totalEarnings,

      //====================================================================
      // Dates
      //====================================================================

      createdAt:
          createdAt ??
              this.createdAt,

      approvedAt:
          approvedAt ??
              this.approvedAt,

      approvedBy:
          approvedBy ??
              this.approvedBy,
    );
  }

  //==========================================================================
  // Firestore
  //==========================================================================
    factory Driver.fromMap(
    Map<String, dynamic> map,
  ) {
    return Driver(
      //====================================================================
      // Identity
      //====================================================================

      uid: map['uid'] ?? '',
      todaId: map['todaId'] ?? '',
      vehicleId: map['vehicleId'] ?? '',

      //====================================================================
      // License
      //====================================================================

      licenseNumber:
          map['licenseNumber'] ?? '',

      licenseExpiry:
          DateTime.parse(
        map['licenseExpiry'],
      ),

      //====================================================================
      // Uploaded Documents
      //====================================================================

      profilePhotoUrl:
          map['profilePhotoUrl'] ?? '',

      driverLicenseFrontUrl:
          map['driverLicenseFrontUrl'] ?? '',

      driverLicenseBackUrl:
          map['driverLicenseBackUrl'] ?? '',

      governmentIdUrl:
          map['governmentIdUrl'] ?? '',

      orDocumentUrl:
          map['orDocumentUrl'] ?? '',

      crDocumentUrl:
          map['crDocumentUrl'] ?? '',

      vehiclePhotoUrl:
          map['vehiclePhotoUrl'] ?? '',

      //====================================================================
      // Driver Status
      //====================================================================

      driverStatus:
          map['driverStatus'] ??
              'pending',

      isOnline:
          map['isOnline'] ?? false,

      isAvailable:
          map['isAvailable'] ?? true,

      currentBookingId:
          map['currentBookingId']
              as String?,

      currentLatitude:
          map['currentLatitude'] != null
              ? (map['currentLatitude']
                      as num)
                  .toDouble()
              : null,

      currentLongitude:
          map['currentLongitude'] != null
              ? (map['currentLongitude']
                      as num)
                  .toDouble()
              : null,

      //====================================================================
      // Statistics
      //====================================================================

      rating:
          (map['rating'] ?? 0)
              .toDouble(),

      completedTrips:
          map['completedTrips'] ?? 0,

      totalEarnings:
          (map['totalEarnings'] ?? 0)
              .toDouble(),

      //====================================================================
      // Dates
      //====================================================================

      createdAt:
          DateTime.parse(
        map['createdAt'],
      ),

      approvedAt:
          map['approvedAt'] != null
              ? DateTime.parse(
                  map['approvedAt'],
                )
              : null,

      approvedBy:
          map['approvedBy']
              as String?,
    );
  }

  //==========================================================================
  // Firestore Serialization
  //==========================================================================
    Map<String, dynamic> toMap() {
    return {
      //====================================================================
      // Identity
      //====================================================================

      'uid': uid,
      'todaId': todaId,
      'vehicleId': vehicleId,

      //====================================================================
      // License
      //====================================================================

      'licenseNumber':
          licenseNumber,

      'licenseExpiry':
          licenseExpiry
              .toIso8601String(),

      //====================================================================
      // Uploaded Documents
      //====================================================================

      'profilePhotoUrl':
          profilePhotoUrl,

      'driverLicenseFrontUrl':
          driverLicenseFrontUrl,

      'driverLicenseBackUrl':
          driverLicenseBackUrl,

      'governmentIdUrl':
          governmentIdUrl,

      'orDocumentUrl':
          orDocumentUrl,

      'crDocumentUrl':
          crDocumentUrl,

      'vehiclePhotoUrl':
          vehiclePhotoUrl,

      //====================================================================
      // Driver Status
      //====================================================================

      'driverStatus':
          driverStatus,

      'isOnline':
          isOnline,

      'isAvailable':
          isAvailable,

      'currentBookingId':
          currentBookingId,

      'currentLatitude':
          currentLatitude,

      'currentLongitude':
          currentLongitude,

      //====================================================================
      // Statistics
      //====================================================================

      'rating':
          rating,

      'completedTrips':
          completedTrips,

      'totalEarnings':
          totalEarnings,

      //====================================================================
      // Dates
      //====================================================================

      'createdAt':
          createdAt
              .toIso8601String(),

      'approvedAt':
          approvedAt
              ?.toIso8601String(),

      'approvedBy':
          approvedBy,
    };
  }

  //==========================================================================
  // Equatable
  //==========================================================================
    @override
  List<Object?> get props => [
        //====================================================================
        // Identity
        //====================================================================

        uid,
        todaId,
        vehicleId,

        //====================================================================
        // License
        //====================================================================

        licenseNumber,
        licenseExpiry,

        //====================================================================
        // Uploaded Documents
        //====================================================================

        profilePhotoUrl,
        driverLicenseFrontUrl,
        driverLicenseBackUrl,
        governmentIdUrl,
        orDocumentUrl,
        crDocumentUrl,
        vehiclePhotoUrl,

        //====================================================================
        // Driver Status
        //====================================================================

        driverStatus,
        isOnline,
        isAvailable,
        currentBookingId,
        currentLatitude,
        currentLongitude,

        //====================================================================
        // Statistics
        //====================================================================

        rating,
        completedTrips,
        totalEarnings,

        //====================================================================
        // Dates
        //====================================================================

        createdAt,
        approvedAt,
        approvedBy,
      ];
}