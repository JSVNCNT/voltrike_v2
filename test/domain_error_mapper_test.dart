import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/errors/domain_error_mapper.dart';

void main() {
  test('maps an existing registration email without blaming connectivity', () {
    final error = FirebaseAuthException(code: 'email-already-in-use');

    expect(
      DomainErrorMapper.message(error),
      'An account already uses this email. Sign in or reset your password.',
    );
  });

  test('maps an actual Firebase Auth network failure to connectivity', () {
    final error = FirebaseAuthException(code: 'network-request-failed');

    expect(
      DomainErrorMapper.message(error),
      'Unable to reach the service. Check your connection and try again.',
    );
  });

  test('does not describe an unknown backend error as connectivity', () {
    expect(
      DomainErrorMapper.message(Exception('backend write failed')),
      'Something went wrong. Please try again or contact support.',
    );
  });
}
