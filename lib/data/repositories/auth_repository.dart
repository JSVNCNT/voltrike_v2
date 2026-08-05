import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class AuthRepository {
  AuthRepository({AuthService? authService, FirebaseFunctions? functions})
    : _authService = authService ?? AuthService.instance,
      _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final AuthService _authService;
  final FirebaseFunctions _functions;

  User? get currentUser => _authService.currentUser;

  bool get isSignedIn => _authService.isSignedIn;

  bool get isEmailVerified => _authService.isEmailVerified;

  Stream<User?> authStateChanges() {
    return _authService.authStateChanges();
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _authService.signIn(email: email, password: password);
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _authService.register(email: email, password: password);
  }

  Future<void> signOut() {
    return _authService.signOut();
  }

  Future<void> sendEmailVerification() async {
    try {
      await _functions
          .httpsCallable('requestBrandedVerificationEmail')
          .call<Map<String, dynamic>>();
    } on FirebaseFunctionsException catch (error) {
      // A new account must never be blocked from verification just because
      // the optional branded provider is unavailable. Firebase Auth sends the
      // same signed verification link as a dependable fallback. A rate-limit
      // response deliberately does not fall back, as a branded message may
      // already have been accepted for delivery.
      if (error.code == 'not-found' ||
          error.code == 'unimplemented' ||
          error.code == 'internal' ||
          error.code == 'unavailable') {
        await _authService.sendEmailVerification();
        return;
      }
      rethrow;
    }
  }

  Future<void> reloadUser() {
    return _authService.reloadUser();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _functions
          .httpsCallable('requestBrandedPasswordResetEmail')
          .call<Map<String, dynamic>>({'email': email.trim()});
    } on FirebaseFunctionsException catch (error) {
      // Preserve password recovery while the branded function is being
      // deployed. Other failures must not trigger a second provider email.
      if (error.code == 'not-found' || error.code == 'unimplemented') {
        await _authService.sendPasswordResetEmail(email);
        return;
      }
      rethrow;
    }
  }

  Future<void> updatePassword(String password) {
    return _authService.updatePassword(password);
  }

  Future<void> deleteAccount() {
    return _authService.deleteAccount();
  }
}
