/// Security switches for the privately shared mobile build.
///
/// The current APK is distributed directly to test phones instead of through
/// an app store, so device attestation and email verification are optional by
/// default. Firebase password authentication, account activity, role, TODA,
/// participant ownership, and booking-state authorization remain mandatory.
abstract final class MobileSecurityConfig {
  static const bool enableAppCheck = bool.fromEnvironment(
    'VOLTRIKE_ENABLE_APP_CHECK',
    defaultValue: false,
  );

  static const bool requireEmailVerification = bool.fromEnvironment(
    'VOLTRIKE_REQUIRE_EMAIL_VERIFICATION',
    defaultValue: false,
  );
}
