import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

enum VerificationEmailDelivery { branded, firebaseFallback, alreadyVerified }

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

  Future<VerificationEmailDelivery> sendEmailVerification() async {
    // Refresh first so pressing resend after opening the verification link
    // recognizes the completed verification instead of sending another email.
    await reloadUser();
    if (isEmailVerified) return VerificationEmailDelivery.alreadyVerified;

    try {
      final result = await _functions
          .httpsCallable('requestBrandedVerificationEmail')
          .call<Map<String, dynamic>>();
      return result.data['alreadyVerified'] == true
          ? VerificationEmailDelivery.alreadyVerified
          : VerificationEmailDelivery.branded;
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
        return VerificationEmailDelivery.firebaseFallback;
      }
      rethrow;
    }
  }

  Future<void> reloadUser() async {
    await _authService.reloadUser();

    // The callable copies Firebase Auth's authoritative status into the user
    // profile for profile/admin displays. This denormalized display update must
    // never prevent sign-in or app recovery when Functions is unavailable.
    try {
      await _functions
          .httpsCallable('syncMyEmailVerification')
          .call<Map<String, dynamic>>();
    } on FirebaseFunctionsException {
      // Best-effort synchronization; access checks use Firebase Auth directly.
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _functions
          .httpsCallable('requestBrandedPasswordResetEmail')
          .call<Map<String, dynamic>>({'email': email.trim()});
    } on FirebaseFunctionsException catch (error) {
      // Preserve password recovery while the branded function is being
      // deployed or its optional email provider is unavailable. Firebase's
      // built-in reset email is the dependable path for the private APK.
      if (error.code == 'not-found' ||
          error.code == 'unimplemented' ||
          error.code == 'internal' ||
          error.code == 'unavailable' ||
          error.code == 'unauthenticated') {
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
