import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DomainException implements Exception {
  const DomainException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DomainErrorMapper {
  const DomainErrorMapper._();

  static String message(Object error) {
    final code = switch (error) {
      FirebaseFunctionsException value => value.code,
      FirebaseAuthException value => value.code,
      FirebaseException value => value.code,
      _ => '',
    };
    return switch (code) {
      'unauthenticated' => 'Your session expired. Sign in again.',
      'permission-denied' => 'This action is not available for your account.',
      'not-found' => 'The requested ride information is unavailable.',
      'already-exists' => 'This action was already submitted.',
      'failed-precondition' => 'The ride has changed. Refresh and try again.',
      'unavailable' || 'deadline-exceeded' =>
        'Service is temporarily unavailable. Check your connection.',
      'invalid-argument' => 'Review the information and try again.',
      _ => 'Something went wrong. Check your connection and try again.',
    };
  }

  static DomainException exception(Object error) {
    return DomainException(message(error));
  }
}
