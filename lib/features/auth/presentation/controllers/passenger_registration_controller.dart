import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/models/passenger.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/user_repository.dart';

class PassengerRegistrationController
    extends StateNotifier<AsyncValue<void>> {
  PassengerRegistrationController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required PassengerRepository passengerRepository,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _passengerRepository = passengerRepository,
        super(const AsyncData(null));

  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final PassengerRepository _passengerRepository;

  Future<void> register({
    required AppUser user,
    required Passenger passenger,
    required String password,
  }) async {
    state = const AsyncLoading();

    try {
      debugPrint('========== PASSENGER REGISTRATION ==========');

      debugPrint('1. Creating Firebase Authentication account...');

      await _authRepository.register(
        email: user.email,
        password: password,
      );

      debugPrint('2. Firebase Authentication SUCCESS');

      final firebaseUser = _authRepository.currentUser;

      debugPrint('3. Current UID: ${firebaseUser?.uid}');

      if (firebaseUser == null) {
        throw Exception(
          'Unable to create account.',
        );
      }

      final appUser = user.copyWith(
        uid: firebaseUser.uid,
      );

      debugPrint('4. Saving AppUser document...');

      await _userRepository.createUser(
        appUser,
      );

      debugPrint('5. AppUser saved successfully');

      final passengerProfile = passenger.copyWith(
        uid: firebaseUser.uid,
        updatedAt: DateTime.now(),
      );

      debugPrint('6. Saving Passenger document...');

      await _passengerRepository.createPassenger(
        passengerProfile,
      );

      debugPrint('7. Passenger saved successfully');

      debugPrint('8. Sending verification email...');

      await _authRepository.sendEmailVerification();

      debugPrint('9. Verification email sent');

      debugPrint('========== REGISTRATION COMPLETE ==========');

      state = const AsyncData(null);
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('========== FIREBASE AUTH ERROR ==========');
      debugPrint('Code: ${e.code}');
      debugPrint('Message: ${e.message}');
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      debugPrint('========== UNKNOWN ERROR ==========');
      debugPrint(e.toString());
      debugPrintStack(stackTrace: stackTrace);

      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }
}