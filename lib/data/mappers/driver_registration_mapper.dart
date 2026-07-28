import '../models/app_user.dart';
import '../models/driver.dart';
import '../models/driver_registration_data.dart';
import '../models/vehicle.dart';

class DriverRegistrationMapper {
  const DriverRegistrationMapper._();

  //==========================================================================
  // App User
  //==========================================================================

  static AppUser toAppUser({
    required String uid,
    required DriverRegistrationData registration,
    required String profilePhotoUrl,
  }) {
    final now = DateTime.now();

    return AppUser(
      uid: uid,
      email: registration.email,
      firstName: registration.firstName,
      middleName: registration.middleName,
      lastName: registration.lastName,
      dateOfBirth: registration.dateOfBirth,
      phoneNumber: registration.phoneNumber,
      role: 'driver',
      todaId: registration.todaId,
      termsAcceptedAt: registration.termsAcceptedAt,
      privacyAcceptedAt: registration.privacyAcceptedAt,
      termsVersion: registration.termsVersion,
      privacyVersion: registration.privacyVersion,
      profileImage: profilePhotoUrl,
      emailVerified: false,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  //==========================================================================
  // Driver
  //==========================================================================

  static Driver toDriver({
    required String uid,
    required String vehicleId,
    required DriverRegistrationData registration,
    required String profilePhotoUrl,
    required String driverLicenseFrontUrl,
    required String driverLicenseBackUrl,
    required String governmentIdUrl,
    required String orDocumentUrl,
    required String crDocumentUrl,
    required String vehiclePhotoUrl,
  }) {
    return Driver(
      //======================================================================
      // Identity
      //======================================================================
      uid: uid,
      todaId: registration.todaId,
      vehicleId: vehicleId,

      //======================================================================
      // License
      //======================================================================
      // The applicant no longer self-enters licence metadata. The assigned
      // TODA records these values after reviewing the captured licence image.
      licenseNumber: '',
      licenseExpiry: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),

      //======================================================================
      // Uploaded Documents
      //======================================================================
      profilePhotoUrl: profilePhotoUrl,
      driverLicenseFrontUrl: driverLicenseFrontUrl,
      driverLicenseBackUrl: driverLicenseBackUrl,
      governmentIdUrl: governmentIdUrl,
      orDocumentUrl: orDocumentUrl,
      crDocumentUrl: crDocumentUrl,
      vehiclePhotoUrl: vehiclePhotoUrl,

      //======================================================================
      // Driver Status
      //======================================================================
      driverStatus: 'pending',
      isOnline: false,
      // Pending drivers cannot receive offers until their selected TODA has
      // reviewed and approved the submitted registration.
      isAvailable: false,

      currentBookingId: null,
      currentLatitude: null,
      currentLongitude: null,

      //======================================================================
      // Statistics
      //======================================================================
      rating: 0,
      ratingCount: 0,
      completedTrips: 0,
      totalEarnings: 0,

      //======================================================================
      // Dates
      //======================================================================
      createdAt: DateTime.now(),
      approvedAt: null,
      approvedBy: null,
    );
  }

  //==========================================================================
  // Vehicle
  //==========================================================================

  static Vehicle toVehicle({
    required String uid,
    required String vehicleId,
    required DriverRegistrationData registration,
  }) {
    return Vehicle(
      id: vehicleId,
      driverId: uid,
      plateNumber: registration.plateNumber,
      vehicleNumber: registration.vehicleType,
      model: '${registration.vehicleBrand} ${registration.vehicleModel}',
      color: registration.vehicleColor,
      capacity: registration.seatingCapacity,
      isVerified: false,
      createdAt: DateTime.now(),
    );
  }
}
