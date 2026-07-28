import 'dart:io';

import '../../../data/models/driver_registration_data.dart';

enum DriverRegistrationReviewSection {
  personal,
  assignment,
  vehicle,
  documents,
}

class DriverRegistrationReviewIssue {
  const DriverRegistrationReviewIssue({
    required this.section,
    required this.message,
  });

  final DriverRegistrationReviewSection section;
  final String message;
}

class DriverRegistrationReviewPolicy {
  const DriverRegistrationReviewPolicy._();

  static DriverRegistrationReviewIssue? firstIssue(
    DriverRegistrationData registration, {
    DateTime? today,
  }) {
    final sourceToday = today ?? DateTime.now();
    final currentDate = DateTime(
      sourceToday.year,
      sourceToday.month,
      sourceToday.day,
    );
    final birthDate = registration.dateOfBirth;
    if (registration.firstName.trim().isEmpty ||
        registration.lastName.trim().isEmpty ||
        birthDate == null ||
        registration.phoneNumber.trim().isEmpty ||
        registration.email.trim().isEmpty ||
        registration.password.isEmpty) {
      return const DriverRegistrationReviewIssue(
        section: DriverRegistrationReviewSection.personal,
        message: 'Complete your personal and account information.',
      );
    }
    final eighteenthBirthday = DateTime(
      birthDate.year + 18,
      birthDate.month,
      birthDate.day,
    );
    if (eighteenthBirthday.isAfter(currentDate)) {
      return const DriverRegistrationReviewIssue(
        section: DriverRegistrationReviewSection.personal,
        message: 'Driver applicants must be at least 18 years old.',
      );
    }

    if ((registration.region ?? '').trim().isEmpty ||
        (registration.province ?? '').trim().isEmpty ||
        (registration.city ?? '').trim().isEmpty ||
        (registration.barangay ?? '').trim().isEmpty ||
        registration.todaId.trim().isEmpty) {
      return const DriverRegistrationReviewIssue(
        section: DriverRegistrationReviewSection.assignment,
        message: 'Complete your address and TODA assignment.',
      );
    }

    final validVehicleType =
        registration.vehicleType == 'E-Trike' ||
        registration.vehicleType == 'Electric Tuktuk';
    final validCapacity = registration.vehicleType == 'E-Trike'
        ? registration.seatingCapacity == 2
        : registration.seatingCapacity >= 3 &&
              registration.seatingCapacity <= 4;
    if (!validVehicleType ||
        !validCapacity ||
        registration.plateNumber.trim().isEmpty ||
        registration.vehicleBrand.trim().isEmpty ||
        registration.vehicleModel.trim().isEmpty ||
        registration.vehicleColor.trim().isEmpty) {
      return const DriverRegistrationReviewIssue(
        section: DriverRegistrationReviewSection.vehicle,
        message: 'Complete your vehicle information and passenger capacity.',
      );
    }

    final documentPaths = <String?>[
      registration.profilePhoto,
      registration.driverLicenseFront,
      registration.driverLicenseBack,
      registration.governmentId,
      registration.orDocument,
      registration.crDocument,
      registration.vehiclePhoto,
    ];
    final documentsReady = documentPaths.every((path) {
      if (path == null || path.trim().isEmpty) return false;
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    });
    if (!documentsReady) {
      return const DriverRegistrationReviewIssue(
        section: DriverRegistrationReviewSection.documents,
        message: 'Capture all required registration images again.',
      );
    }

    return null;
  }
}
