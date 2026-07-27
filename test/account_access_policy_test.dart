import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/app_user.dart';
import 'package:voltrike_v2/data/models/driver.dart';
import 'package:voltrike_v2/features/auth/domain/account_access_policy.dart';

void main() {
  final now = DateTime(2026, 7, 27);

  AppUser user({String role = 'passenger', bool isActive = true}) => AppUser(
    uid: 'user-1',
    email: 'user@example.com',
    firstName: 'Test',
    middleName: '',
    lastName: 'User',
    phoneNumber: '09170000000',
    role: role,
    profileImage: '',
    emailVerified: true,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  Driver driver(String status) => Driver(
    uid: 'user-1',
    todaId: 'toda-1',
    vehicleId: 'vehicle-1',
    licenseNumber: 'license-1',
    licenseExpiry: now.add(const Duration(days: 365)),
    profilePhotoUrl: '',
    driverLicenseFrontUrl: '',
    driverLicenseBackUrl: '',
    governmentIdUrl: '',
    orDocumentUrl: '',
    crDocumentUrl: '',
    vehiclePhotoUrl: '',
    driverStatus: status,
    isOnline: false,
    isAvailable: false,
    rating: 0,
    ratingCount: 0,
    completedTrips: 0,
    totalEarnings: 0,
    createdAt: now,
  );

  test('inactive passenger is suspended', () {
    expect(
      AccountAccessPolicy.evaluate(user: user(isActive: false)),
      AccountAccessStatus.suspended,
    );
  });

  test('suspended driver is suspended even when user remains active', () {
    expect(
      AccountAccessPolicy.evaluate(
        user: user(role: 'driver'),
        driver: driver('suspended'),
      ),
      AccountAccessStatus.suspended,
    );
  });

  test('only approved active driver gets app access', () {
    expect(
      AccountAccessPolicy.evaluate(
        user: user(role: 'driver'),
        driver: driver('pending'),
      ),
      AccountAccessStatus.underReview,
    );
    expect(
      AccountAccessPolicy.evaluate(
        user: user(role: 'driver'),
        driver: driver('approved'),
      ),
      AccountAccessStatus.active,
    );
  });
}
