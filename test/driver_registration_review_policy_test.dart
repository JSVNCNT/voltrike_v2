import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/driver_registration_data.dart';
import 'package:voltrike_v2/features/auth/services/driver_registration_review_policy.dart';

void main() {
  late Directory temporaryDirectory;
  late List<File> documents;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'voltrike-review-',
    );
    documents = List.generate(
      7,
      (index) =>
          File('${temporaryDirectory.path}${Platform.pathSeparator}$index.jpg')
            ..writeAsBytesSync(<int>[1, 2, 3]),
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('accepts a complete registration', () {
    final issue = DriverRegistrationReviewPolicy.firstIssue(
      _completeRegistration(documents),
      today: DateTime(2026, 7, 29),
    );

    expect(issue, isNull);
  });

  test('sends an underage applicant back to personal details', () {
    final issue = DriverRegistrationReviewPolicy.firstIssue(
      _completeRegistration(
        documents,
      ).copyWith(dateOfBirth: DateTime(2010, 1, 1)),
      today: DateTime(2026, 7, 29),
    );

    expect(issue?.section, DriverRegistrationReviewSection.personal);
    expect(issue?.message, contains('at least 18'));
  });

  test('rejects an electric tuktuk capacity outside three to four', () {
    final issue = DriverRegistrationReviewPolicy.firstIssue(
      _completeRegistration(documents).copyWith(seatingCapacity: 5),
      today: DateTime(2026, 7, 29),
    );

    expect(issue?.section, DriverRegistrationReviewSection.vehicle);
  });

  test('requires every prepared document image', () {
    documents.last.deleteSync();

    final issue = DriverRegistrationReviewPolicy.firstIssue(
      _completeRegistration(documents),
      today: DateTime(2026, 7, 29),
    );

    expect(issue?.section, DriverRegistrationReviewSection.documents);
  });
}

DriverRegistrationData _completeRegistration(List<File> documents) {
  return DriverRegistrationData(
    firstName: 'Juan',
    middleName: 'Santos',
    lastName: 'Dela Cruz',
    dateOfBirth: DateTime(1990, 1, 1),
    phoneNumber: '09171234567',
    email: 'juan@example.com',
    password: 'correct-horse-battery-staple',
    region: '06',
    province: '0645',
    city: '064501',
    barangay: '064501001',
    todaId: 'toda-1',
    plateNumber: 'ABC 1234',
    vehicleType: 'Electric Tuktuk',
    vehicleBrand: 'Voltrike',
    vehicleModel: 'VT4',
    vehicleColor: 'Green',
    seatingCapacity: 4,
    profilePhoto: documents[0].path,
    driverLicenseFront: documents[1].path,
    driverLicenseBack: documents[2].path,
    governmentId: documents[3].path,
    orDocument: documents[4].path,
    crDocument: documents[5].path,
    vehiclePhoto: documents[6].path,
  );
}
