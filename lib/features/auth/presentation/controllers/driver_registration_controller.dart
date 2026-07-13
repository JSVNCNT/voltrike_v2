import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/mappers/driver_registration_mapper.dart';

import '../../../../data/models/driver_registration_data.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/storage_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/repositories/vehicle_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DriverRegistrationController
    extends StateNotifier<AsyncValue<void>> {
  DriverRegistrationController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DriverRepository driverRepository,
    required VehicleRepository vehicleRepository,
    required StorageRepository storageRepository,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _driverRepository = driverRepository,
        _vehicleRepository = vehicleRepository,
        _storageRepository = storageRepository,
        super(const AsyncData(null));

  final AuthRepository _authRepository;

  final UserRepository _userRepository;

  final DriverRepository _driverRepository;

  final VehicleRepository _vehicleRepository;

  final StorageRepository _storageRepository;

  final Uuid _uuid = const Uuid();

  Future<String> _uploadImage({
    required String uid,
    required String fileName,
    required String? localPath,
  }) async {
    if (localPath == null || localPath.isEmpty) {
      return '';
    }

    return _storageRepository.uploadFile(
      path: 'drivers/$uid/$fileName',
      file: File(localPath),
    );
  }

 Future<void> register(
  DriverRegistrationData registration,
) async {
  state = const AsyncLoading();

  try {
    debugPrint('========== DRIVER REGISTRATION ==========');

    debugPrint('1. Creating Firebase Authentication account...');

    await _authRepository.register(
      email: registration.email,
      password: registration.password,
    );

    debugPrint('2. Firebase Authentication SUCCESS');

    final firebaseUser = _authRepository.currentUser;

    debugPrint('3. UID: ${firebaseUser?.uid}');

    if (firebaseUser == null) {
      throw Exception('Unable to create account.');
    }

    final uid = firebaseUser.uid;
    final vehicleId = _uuid.v4();

    debugPrint('4. Uploading Profile Photo...');
    final profilePhotoUrl = await _uploadImage(
      uid: uid,
      fileName: 'profile.jpg',
      localPath: registration.profilePhoto,
    );

    debugPrint('5. Uploading Driver License Front...');
    final driverLicenseFrontUrl = await _uploadImage(
      uid: uid,
      fileName: 'license_front.jpg',
      localPath: registration.driverLicenseFront,
    );

    debugPrint('6. Uploading Driver License Back...');
    final driverLicenseBackUrl = await _uploadImage(
      uid: uid,
      fileName: 'license_back.jpg',
      localPath: registration.driverLicenseBack,
    );

    debugPrint('7. Uploading Government ID...');
    final governmentIdUrl = await _uploadImage(
      uid: uid,
      fileName: 'government_id.jpg',
      localPath: registration.governmentId,
    );

    debugPrint('8. Uploading OR...');
    final orDocumentUrl = await _uploadImage(
      uid: uid,
      fileName: 'or.jpg',
      localPath: registration.orDocument,
    );

    debugPrint('9. Uploading CR...');
    final crDocumentUrl = await _uploadImage(
      uid: uid,
      fileName: 'cr.jpg',
      localPath: registration.crDocument,
    );

    debugPrint('10. Uploading Vehicle Photo...');
    final vehiclePhotoUrl = await _uploadImage(
      uid: uid,
      fileName: 'vehicle.jpg',
      localPath: registration.vehiclePhoto,
    );

    debugPrint('11. All uploads completed');

    final appUser = DriverRegistrationMapper.toAppUser(
      uid: uid,
      registration: registration,
      profilePhotoUrl: profilePhotoUrl,
    );

    final vehicle = DriverRegistrationMapper.toVehicle(
      uid: uid,
      vehicleId: vehicleId,
      registration: registration,
    );

    final driver = DriverRegistrationMapper.toDriver(
      uid: uid,
      vehicleId: vehicleId,
      registration: registration,
      profilePhotoUrl: profilePhotoUrl,
      driverLicenseFrontUrl: driverLicenseFrontUrl,
      driverLicenseBackUrl: driverLicenseBackUrl,
      governmentIdUrl: governmentIdUrl,
      orDocumentUrl: orDocumentUrl,
      crDocumentUrl: crDocumentUrl,
      vehiclePhotoUrl: vehiclePhotoUrl,
    );

    debugPrint('12. Saving AppUser...');
    await _userRepository.createUser(appUser);

    debugPrint('13. AppUser saved');

    debugPrint('14. Saving Vehicle...');
    await _vehicleRepository.createVehicle(vehicle);

    debugPrint('15. Vehicle saved');

    debugPrint('16. Saving Driver...');
    await _driverRepository.createDriver(driver);

    debugPrint('17. Driver saved');

    debugPrint('18. Sending verification email...');
    await _authRepository.sendEmailVerification();

    debugPrint('19. Verification email sent');

    debugPrint('========== DRIVER REGISTRATION COMPLETE ==========');

    state = const AsyncData(null);
  } on FirebaseAuthException catch (e, stackTrace) {
    debugPrint('========== FIREBASE AUTH ERROR ==========');
    debugPrint('Code: ${e.code}');
    debugPrint('Message: ${e.message}');
    debugPrintStack(stackTrace: stackTrace);

    state = AsyncError(e, stackTrace);
    rethrow;
  } catch (e, stackTrace) {
    debugPrint('========== DRIVER REGISTRATION ERROR ==========');
    debugPrint(e.toString());
    debugPrintStack(stackTrace: stackTrace);

    state = AsyncError(e, stackTrace);
    rethrow;
    }
  }
} 
