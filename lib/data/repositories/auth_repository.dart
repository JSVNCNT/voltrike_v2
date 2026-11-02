import 'package:firebase_auth/firebase_auth.dart';

import '../../core/services/voltrike_api.dart';
import '../services/auth_service.dart';

enum VerificationEmailDelivery { branded, firebaseFallback, alreadyVerified }

class AuthRepository {
  AuthRepository({AuthService? authService, VoltrikeApi? api})
    : _authService = authService ?? AuthService.instance,
      _api = api ?? VoltrikeApi.instance;

  final AuthService _authService;
  final VoltrikeApi _api;

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
      final result = await _api.operation(
        'requestBrandedVerificationEmail',
        {},
      );
      return result['alreadyVerified'] == true
          ? VerificationEmailDelivery.alreadyVerified
          : VerificationEmailDelivery.branded;
    } on VoltrikeApiException catch (error) {
      // A new account must never be blocked from verification just because
      // the optional branded provider is unavailable. Firebase Auth sends the
      // same signed verification link as a dependable fallback. A rate-limit
      // response deliberately does not fall back, as a branded message may
      // already have been accepted for delivery.
      if (_allowsFirebaseFallback(error)) {
        await _authService.sendEmailVerification();
        return VerificationEmailDelivery.firebaseFallback;
      }
      rethrow;
    }
  }

  Future<void> reloadUser() async {
    await _authService.reloadUser();

    // The API copies Firebase Auth's authoritative status into the user
    // profile for profile/admin displays. This denormalized display update must
    // never prevent sign-in or app recovery when the API is unavailable.
    try {
      await _api.operation('syncMyEmailVerification', {});
    } on VoltrikeApiException {
      // Best-effort synchronization; access checks use Firebase Auth directly.
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _api.requestPasswordResetEmail(email);
    } on VoltrikeApiException catch (error) {
      // Preserve password recovery while the branded service is being
      // deployed or its optional email provider is unavailable. Firebase's
      // built-in reset email is the dependable path for the private APK.
      if (_allowsFirebaseFallback(error) || error.code == 'unauthenticated') {
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

  static bool _allowsFirebaseFallback(VoltrikeApiException error) {
    return const {
      'not-found',
      'unimplemented',
      'internal',
      'unavailable',
    }.contains(error.code?.replaceAll('_', '-'));
  }
}
