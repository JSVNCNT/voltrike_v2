import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/mappers/driver_registration_mapper.dart';
import '../../../../data/models/driver_registration_data.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/registration_repository.dart';
import '../../../../data/repositories/storage_repository.dart';

class DriverRegistrationController extends StateNotifier<AsyncValue<void>> {
  DriverRegistrationController({
    required AuthRepository authRepository,
    required RegistrationRepository registrationRepository,
    required StorageRepository storageRepository,
  }) : _authRepository = authRepository,
       _registrationRepository = registrationRepository,
       _storageRepository = storageRepository,
       super(const AsyncData(null));

  final AuthRepository _authRepository;

  final RegistrationRepository _registrationRepository;

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

  Future<void> register(DriverRegistrationData registration) async {
    state = const AsyncLoading();
    var accountCreated = false;
    var registrationCommitted = false;
    final uploadedUrls = <String>[];

    try {
      debugPrint('========== DRIVER REGISTRATION ==========');

      debugPrint('1. Creating Firebase Authentication account...');

      final (firebaseUser, created) = await _createOrResumeAccount(
        email: registration.email,
        password: registration.password,
      );
      accountCreated = created;

      debugPrint('2. Firebase Authentication SUCCESS');

      debugPrint('3. UID: ${firebaseUser.uid}');

      final uid = firebaseUser.uid;
      final vehicleId = _uuid.v4();

      debugPrint('4. Uploading Profile Photo...');
      final profilePhotoUrl = await _uploadImage(
        uid: uid,
        fileName: 'profile.jpg',
        localPath: registration.profilePhoto,
      );
      uploadedUrls.add(profilePhotoUrl);

      debugPrint('5. Uploading Driver License Front...');
      final driverLicenseFrontUrl = await _uploadImage(
        uid: uid,
        fileName: 'license_front.jpg',
        localPath: registration.driverLicenseFront,
      );
      uploadedUrls.add(driverLicenseFrontUrl);

      debugPrint('6. Uploading Driver License Back...');
      final driverLicenseBackUrl = await _uploadImage(
        uid: uid,
        fileName: 'license_back.jpg',
        localPath: registration.driverLicenseBack,
      );
      uploadedUrls.add(driverLicenseBackUrl);

      debugPrint('7. Uploading Government ID...');
      final governmentIdUrl = await _uploadImage(
        uid: uid,
        fileName: 'government_id.jpg',
        localPath: registration.governmentId,
      );
      uploadedUrls.add(governmentIdUrl);

      debugPrint('8. Uploading OR...');
      final orDocumentUrl = await _uploadImage(
        uid: uid,
        fileName: 'or.jpg',
        localPath: registration.orDocument,
      );
      uploadedUrls.add(orDocumentUrl);

      debugPrint('9. Uploading CR...');
      final crDocumentUrl = await _uploadImage(
        uid: uid,
        fileName: 'cr.jpg',
        localPath: registration.crDocument,
      );
      uploadedUrls.add(crDocumentUrl);

      debugPrint('10. Uploading Vehicle Photo...');
      final vehiclePhotoUrl = await _uploadImage(
        uid: uid,
        fileName: 'vehicle.jpg',
        localPath: registration.vehiclePhoto,
      );
      uploadedUrls.add(vehiclePhotoUrl);

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

      debugPrint('12. Saving registration documents...');
      await _registrationRepository.createDriverRegistration(
        user: appUser,
        driver: driver,
        vehicle: vehicle,
      );
      registrationCommitted = true;

      debugPrint('13. Registration documents saved');

      debugPrint('14. Sending verification email...');
      try {
        await _authRepository.sendEmailVerification();
        debugPrint('15. Verification email sent');
      } catch (error) {
        // Onboarding is complete and verification can be resent later.
        debugPrint('15. Verification email could not be sent: $error');
      }

      debugPrint('========== DRIVER REGISTRATION COMPLETE ==========');

      state = const AsyncData(null);
    } on FirebaseAuthException catch (e, stackTrace) {
      if (!registrationCommitted) {
        await _rollBackIncompleteRegistration(
          uploadedUrls,
          deleteAccount: accountCreated,
        );
      }
      debugPrint('========== FIREBASE AUTH ERROR ==========');
      debugPrint('Code: ${e.code}');
      debugPrint('Message: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      if (!registrationCommitted) {
        await _rollBackIncompleteRegistration(
          uploadedUrls,
          deleteAccount: accountCreated,
        );
      }
      debugPrint('========== DRIVER REGISTRATION ERROR ==========');
      debugPrint(e.toString());
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  Future<void> _rollBackIncompleteRegistration(
    List<String> uploadedUrls, {
    required bool deleteAccount,
  }) async {
    for (final url in uploadedUrls.reversed) {
      if (url.isEmpty) continue;
      try {
        await _storageRepository.deleteFile(url);
      } catch (error) {
        debugPrint('Could not remove incomplete registration upload: $error');
      }
    }

    if (deleteAccount) {
      try {
        await _authRepository.deleteAccount();
        debugPrint('Rolled back incomplete Firebase Authentication account.');
      } catch (error) {
        debugPrint('Could not roll back incomplete account: $error');
      }
    }
  }

  Future<(User, bool)> _createOrResumeAccount({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _authRepository.register(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Unable to create account.');
      }
      return (user, true);
    } on FirebaseAuthException catch (error) {
      final currentUser = _authRepository.currentUser;
      final sameSignedInAccount =
          currentUser != null &&
          currentUser.email?.trim().toLowerCase() == email.trim().toLowerCase();

      if (error.code != 'email-already-in-use' || !sameSignedInAccount) {
        rethrow;
      }

      final registrationExists = await _registrationRepository
          .driverRegistrationExists(currentUser.uid);
      if (registrationExists) {
        rethrow;
      }

      debugPrint('Resuming incomplete driver registration.');
      return (currentUser, false);
    }
  }
}
