import 'package:equatable/equatable.dart';

/// Temporary model used during the multi-step
/// driver registration process.
///
/// This model is NOT stored in Firestore.
/// It only holds the data while the driver
/// completes the registration wizard.
class DriverRegistrationData extends Equatable {
  const DriverRegistrationData({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.phoneNumber = '',
    this.email = '',
    this.password = '',

    this.licenseNumber = '',
    this.licenseExpiry,

    this.region = '',
    this.province = '',
    this.city = '',
    this.barangay = '',
    this.todaId = '',

    this.plateNumber = '',
    this.vehicleType = '',
    this.vehicleBrand = '',
    this.vehicleModel = '',
    this.vehicleColor = '',
    this.seatingCapacity = 3,

    this.driverLicenseFront,
    this.driverLicenseBack,
    this.governmentId,
    this.orDocument,
    this.crDocument,
    this.vehiclePhoto,
    this.profilePhoto,
  });

  //==========================================================================
  // STEP 1
  //==========================================================================

  final String firstName;
  final String middleName;
  final String lastName;

  final String phoneNumber;

  final String email;

  final String password;

  //==========================================================================
  // STEP 2
  //==========================================================================

  final String licenseNumber;

  final DateTime? licenseExpiry;

  final String? region;
  final String? province;
  final String? city;
  final String? barangay;

  final String todaId;

  //==========================================================================
  // STEP 3
  //==========================================================================

  final String plateNumber;

  final String vehicleType;

  /// Honda, Yamaha, Bajaj, etc.
  final String vehicleBrand;

  /// TMX125, CT100, RE, etc.
  final String vehicleModel;

  final String vehicleColor;

  final int seatingCapacity;

  //==========================================================================
  // STEP 4
  //==========================================================================

  final String? driverLicenseFront;

  final String? driverLicenseBack;

  final String? governmentId;

  final String? orDocument;

  final String? crDocument;

  final String? vehiclePhoto;

  final String? profilePhoto;

  //==========================================================================
  // Helpers
  //==========================================================================

  String get fullName {
    if (middleName.trim().isEmpty) {
      return '$firstName $lastName';
    }

    return '$firstName $middleName $lastName';
  }

  DriverRegistrationData copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? phoneNumber,
    String? email,
    String? password,

    String? licenseNumber,
    DateTime? licenseExpiry,

    String? region,
    String? province,
    String? city,
    String? barangay,
    String? todaId,

    String? plateNumber,
    String? vehicleType,
    String? vehicleBrand,
    String? vehicleModel,
    String? vehicleColor,
    int? seatingCapacity,

    String? driverLicenseFront,
    String? driverLicenseBack,
    String? governmentId,
    String? orDocument,
    String? crDocument,
    String? vehiclePhoto,
    String? profilePhoto,
  }) {
    return DriverRegistrationData(
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      password: password ?? this.password,

      licenseNumber:
          licenseNumber ?? this.licenseNumber,

      licenseExpiry:
          licenseExpiry ?? this.licenseExpiry,

      region: region ?? this.region,
      province: province ?? this.province,
      city: city ?? this.city,
      barangay: barangay ?? this.barangay,
      todaId: todaId ?? this.todaId,

      plateNumber:
          plateNumber ?? this.plateNumber,

      vehicleType:
          vehicleType ?? this.vehicleType,

      vehicleBrand:
          vehicleBrand ?? this.vehicleBrand,

      vehicleModel:
          vehicleModel ?? this.vehicleModel,

      vehicleColor:
          vehicleColor ?? this.vehicleColor,

      seatingCapacity:
          seatingCapacity ?? this.seatingCapacity,

      driverLicenseFront:
          driverLicenseFront ??
              this.driverLicenseFront,

      driverLicenseBack:
          driverLicenseBack ??
              this.driverLicenseBack,

      governmentId:
          governmentId ?? this.governmentId,

      orDocument:
          orDocument ?? this.orDocument,

      crDocument:
          crDocument ?? this.crDocument,

      vehiclePhoto:
          vehiclePhoto ?? this.vehiclePhoto,

      profilePhoto:
          profilePhoto ?? this.profilePhoto,
    );
  }

  @override
  List<Object?> get props => [
        firstName,
        middleName,
        lastName,
        phoneNumber,
        email,
        password,

        licenseNumber,
        licenseExpiry,

        region,
        province,
        city,
        barangay,
        todaId,

        plateNumber,
        vehicleType,
        vehicleBrand,
        vehicleModel,
        vehicleColor,
        seatingCapacity,

        driverLicenseFront,
        driverLicenseBack,
        governmentId,
        orDocument,
        crDocument,
        vehiclePhoto,
        profilePhoto,
      ];
}