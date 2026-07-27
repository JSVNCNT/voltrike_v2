import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

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
      PlatformException value => value.code,
      _ => '',
    };
    return switch (code) {
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' =>
        'An account already uses this email. Sign in or reset your password.',
      'weak-password' => 'Use a stronger password and try again.',
      'operation-not-allowed' =>
        'Email registration is currently unavailable. Contact support.',
      'network-request-failed' =>
        'Unable to reach the service. Check your connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Wait a few minutes and try again.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'The email or password is incorrect.',
      'requires-recent-login' => 'Sign in again before continuing.',
      'unauthenticated' => 'Your session expired. Sign in again.',
      'permission-denied' || 'unauthorized' =>
        'The service rejected this request. Contact support if it continues.',
      'not-found' => 'The requested ride information is unavailable.',
      'object-not-found' => 'The selected file is no longer available.',
      'already-exists' => 'This action was already submitted.',
      'failed-precondition' => 'The ride has changed. Refresh and try again.',
      'unavailable' || 'deadline-exceeded' =>
        'Service is temporarily unavailable. Check your connection.',
      'invalid-argument' => 'Review the information and try again.',
      'quota-exceeded' => 'The service limit was reached. Try again later.',
      'canceled' => 'The operation was canceled. Please try again.',
      _ => 'Something went wrong. Please try again or contact support.',
    };
  }

  static DomainException exception(Object error) {
    return DomainException(message(error));
  }
}
