import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseAuth get auth => _auth;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() {
    return _auth.authStateChanges();
  }

  bool get isSignedIn => currentUser != null;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() {
    return _auth.signOut();
  }

  Future<void> sendEmailVerification() async {
    await currentUser?.sendEmailVerification();
  }

  Future<void> reloadUser() async {
    await currentUser?.reload();
  }

  bool get isEmailVerified {
    return currentUser?.emailVerified ?? false;
  }

  Future<void> sendPasswordResetEmail(
    String email,
  ) {
    return _auth.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  Future<void> updatePassword(
    String newPassword,
  ) async {
    await currentUser?.updatePassword(newPassword);
  }

  Future<void> deleteAccount() async {
    await currentUser?.delete();
  }
}