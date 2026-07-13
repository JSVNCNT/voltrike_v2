import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/driver_registration_data.dart';

class DriverRegistrationDataNotifier
    extends StateNotifier<DriverRegistrationData> {
  DriverRegistrationDataNotifier()
      : super(const DriverRegistrationData());

  /// Replace the whole object
  void update(DriverRegistrationData data) {
    state = data;
  }

  /// Update only changed values
  void updateData({
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
    state = state.copyWith(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      email: email,
      password: password,

      licenseNumber: licenseNumber,
      licenseExpiry: licenseExpiry,

      region: region,
      province: province,
      city: city,
      barangay: barangay,
      todaId: todaId,

      plateNumber: plateNumber,
      vehicleType: vehicleType,
      vehicleBrand: vehicleBrand,
      vehicleModel: vehicleModel,
      vehicleColor: vehicleColor,
      seatingCapacity: seatingCapacity,

      driverLicenseFront: driverLicenseFront,
      driverLicenseBack: driverLicenseBack,
      governmentId: governmentId,
      orDocument: orDocument,
      crDocument: crDocument,
      vehiclePhoto: vehiclePhoto,
      profilePhoto: profilePhoto,
    );
  }

  /// Reset registration
  void clear() {
    state = const DriverRegistrationData();
  }
}

final driverRegistrationDataProvider =
    StateNotifierProvider<
        DriverRegistrationDataNotifier,
        DriverRegistrationData>(
  (ref) => DriverRegistrationDataNotifier(),
);