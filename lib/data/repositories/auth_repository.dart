import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class AuthRepository {
  AuthRepository({
    AuthService? authService,
  }) : _authService = authService ?? AuthService.instance;

  final AuthService _authService;

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
    return _authService.signIn(
      email: email,
      password: password,
    );
  }


  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _authService.register(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() {
    return _authService.signOut();
  }

  Future<void> sendEmailVerification() {
    return _authService.sendEmailVerification();
  }

  Future<void> reloadUser() {
    return _authService.reloadUser();
  }

  Future<void> sendPasswordResetEmail(
    String email,
  ) {
    return _authService.sendPasswordResetEmail(email);
  }

  Future<void> updatePassword(
    String password,
  ) {
    return _authService.updatePassword(password);
  }

  Future<void> deleteAccount() {
    return _authService.deleteAccount();
  }
}