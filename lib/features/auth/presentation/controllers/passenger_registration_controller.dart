import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/models/passenger.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/registration_repository.dart';

class PassengerRegistrationController extends StateNotifier<AsyncValue<void>> {
  PassengerRegistrationController({
    required AuthRepository authRepository,
    required RegistrationRepository registrationRepository,
  }) : _authRepository = authRepository,
       _registrationRepository = registrationRepository,
       super(const AsyncData(null));

  final AuthRepository _authRepository;
  final RegistrationRepository _registrationRepository;

  Future<void> register({
    required AppUser user,
    required Passenger passenger,
    required String password,
  }) async {
    state = const AsyncLoading();
    var accountCreated = false;
    var registrationCommitted = false;

    try {
      debugPrint('========== PASSENGER REGISTRATION ==========');

      debugPrint('1. Creating Firebase Authentication account...');

      final credential = await _authRepository.register(
        email: user.email,
        password: password,
      );
      accountCreated = true;

      debugPrint('2. Firebase Authentication SUCCESS');

      final firebaseUser = credential.user;

      debugPrint('3. Current UID: ${firebaseUser?.uid}');

      if (firebaseUser == null) {
        throw Exception('Unable to create account.');
      }

      final appUser = user.copyWith(uid: firebaseUser.uid);

      final passengerProfile = passenger.copyWith(
        uid: firebaseUser.uid,
        updatedAt: DateTime.now(),
      );

      debugPrint('4. Saving registration documents...');

      await _registrationRepository.createPassengerRegistration(
        user: appUser,
        passenger: passengerProfile,
      );
      registrationCommitted = true;

      debugPrint('5. Registration documents saved successfully');

      debugPrint('6. Sending verification email...');

      try {
        await _authRepository.sendEmailVerification();
        debugPrint('7. Verification email sent');
      } catch (error) {
        // The account and profile are valid. The verification screens allow
        // the user to retry sending the email, so do not fail registration.
        debugPrint('7. Verification email could not be sent: $error');
      }

      debugPrint('========== REGISTRATION COMPLETE ==========');

      state = const AsyncData(null);
    } on FirebaseAuthException catch (e, stackTrace) {
      if (accountCreated && !registrationCommitted) {
        await _deleteNewAccount();
      }
      debugPrint('========== FIREBASE AUTH ERROR ==========');
      debugPrint('Code: ${e.code}');
      debugPrint('Message: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      if (accountCreated && !registrationCommitted) {
        await _deleteNewAccount();
      }
      debugPrint('========== UNKNOWN ERROR ==========');
      debugPrint(e.toString());
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  Future<void> _deleteNewAccount() async {
    try {
      await _authRepository.deleteAccount();
      debugPrint('Rolled back incomplete Firebase Authentication account.');
    } catch (error) {
      debugPrint('Could not roll back incomplete account: $error');
    }
  }
}
