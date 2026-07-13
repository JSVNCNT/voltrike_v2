import '../models/app_user.dart';
import '../models/driver.dart';
import '../models/driver_registration_data.dart';
import '../models/vehicle.dart';

class DriverRegistrationMapper {
  const DriverRegistrationMapper._();

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
      phoneNumber: registration.phoneNumber,
      role: 'driver',
      todaId: registration.todaId,
      profileImage: profilePhotoUrl,
      emailVerified: false,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

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
      uid: uid,
      todaId: registration.todaId,
      vehicleId: vehicleId,

      licenseNumber: registration.licenseNumber,
      licenseExpiry: registration.licenseExpiry!,

      profilePhotoUrl: profilePhotoUrl,
      driverLicenseFrontUrl: driverLicenseFrontUrl,
      driverLicenseBackUrl: driverLicenseBackUrl,
      governmentIdUrl: governmentIdUrl,
      orDocumentUrl: orDocumentUrl,
      crDocumentUrl: crDocumentUrl,
      vehiclePhotoUrl: vehiclePhotoUrl,

      driverStatus: 'pending',
      isOnline: false,
      rating: 0,
      completedTrips: 0,
      totalEarnings: 0,
      createdAt: DateTime.now(),
      approvedAt: null,
      approvedBy: null,
    );
  }

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

      model:
          '${registration.vehicleBrand} ${registration.vehicleModel}',

      color: registration.vehicleColor,

      capacity: registration.seatingCapacity,

      isVerified: false,

      createdAt: DateTime.now(),
    );
  }
}