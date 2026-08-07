import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/config/mobile_security_config.dart';

void main() {
  test('private mobile build does not require per-device attestation', () {
    expect(MobileSecurityConfig.enableAppCheck, isFalse);
  });

  test('private mobile build permits unverified test accounts', () {
    expect(MobileSecurityConfig.requireEmailVerification, isFalse);
  });
}
