import 'package:equatable/equatable.dart';

class Driver extends Equatable {
  const Driver({
    required this.uid,
    required this.todaId,
    required this.vehicleId,
    required this.licenseNumber,
    required this.licenseExpiry,

    required this.profilePhotoUrl,
    required this.driverLicenseFrontUrl,
    required this.driverLicenseBackUrl,
    required this.governmentIdUrl,
    required this.orDocumentUrl,
    required this.crDocumentUrl,
    required this.vehiclePhotoUrl,

    required this.driverStatus,
    required this.isOnline,
    required this.rating,
    required this.completedTrips,
    required this.totalEarnings,
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
  // Status
  //==========================================================================

  /// pending | approved | rejected | suspended
  final String driverStatus;

  final bool isOnline;

  final double rating;

  final int completedTrips;

  final double totalEarnings;

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

  Driver copyWith({
    String? uid,
    String? todaId,
    String? vehicleId,
    String? licenseNumber,
    DateTime? licenseExpiry,

    String? profilePhotoUrl,
    String? driverLicenseFrontUrl,
    String? driverLicenseBackUrl,
    String? governmentIdUrl,
    String? orDocumentUrl,
    String? crDocumentUrl,
    String? vehiclePhotoUrl,

    String? driverStatus,
    bool? isOnline,
    double? rating,
    int? completedTrips,
    double? totalEarnings,
    DateTime? createdAt,
    DateTime? approvedAt,
    String? approvedBy,
  }) {
    return Driver(
      uid: uid ?? this.uid,
      todaId: todaId ?? this.todaId,
      vehicleId: vehicleId ?? this.vehicleId,
      licenseNumber:
          licenseNumber ?? this.licenseNumber,
      licenseExpiry:
          licenseExpiry ?? this.licenseExpiry,

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

      driverStatus:
          driverStatus ?? this.driverStatus,

      isOnline:
          isOnline ?? this.isOnline,

      rating:
          rating ?? this.rating,

      completedTrips:
          completedTrips ??
              this.completedTrips,

      totalEarnings:
          totalEarnings ??
              this.totalEarnings,

      createdAt:
          createdAt ?? this.createdAt,

      approvedAt:
          approvedAt ?? this.approvedAt,

      approvedBy:
          approvedBy ?? this.approvedBy,
    );
  }
    factory Driver.fromMap(
    Map<String, dynamic> map,
  ) {
    return Driver(
      uid: map['uid'] ?? '',
      todaId: map['todaId'] ?? '',
      vehicleId: map['vehicleId'] ?? '',

      licenseNumber:
          map['licenseNumber'] ?? '',

      licenseExpiry:
          DateTime.parse(
        map['licenseExpiry'],
      ),

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

      driverStatus:
          map['driverStatus'] ??
              'pending',

      isOnline:
          map['isOnline'] ?? false,

      rating:
          (map['rating'] ?? 0)
              .toDouble(),

      completedTrips:
          map['completedTrips'] ?? 0,

      totalEarnings:
          (map['totalEarnings'] ?? 0)
              .toDouble(),

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
          map['approvedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'todaId': todaId,
      'vehicleId': vehicleId,

      'licenseNumber':
          licenseNumber,

      'licenseExpiry':
          licenseExpiry
              .toIso8601String(),

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

      'driverStatus':
          driverStatus,

      'isOnline':
          isOnline,

      'rating':
          rating,

      'completedTrips':
          completedTrips,

      'totalEarnings':
          totalEarnings,

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

  @override
  List<Object?> get props => [
        uid,
        todaId,
        vehicleId,

        licenseNumber,
        licenseExpiry,

        profilePhotoUrl,
        driverLicenseFrontUrl,
        driverLicenseBackUrl,
        governmentIdUrl,
        orDocumentUrl,
        crDocumentUrl,
        vehiclePhotoUrl,

        driverStatus,
        isOnline,
        rating,
        completedTrips,
        totalEarnings,
        createdAt,
        approvedAt,
        approvedBy,
      ];
}