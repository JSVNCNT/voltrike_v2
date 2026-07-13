class AppConstants {
  const AppConstants._();

  // ===========================================================================
  // Application
  // ===========================================================================

  static const String appName = 'VolTrike';

  static const String appTagline =
      'Clean Community Mobility';

  static const String appVersion = '1.0.0';

  // ===========================================================================
  // Animation
  // ===========================================================================

  static const Duration splashDuration =
      Duration(seconds: 2);

  static const Duration animationFast =
      Duration(milliseconds: 150);

  static const Duration animationNormal =
      Duration(milliseconds: 300);

  static const Duration animationSlow =
      Duration(milliseconds: 500);

  // ===========================================================================
  // Layout
  // ===========================================================================

  static const double maxContentWidth = 600;

  static const double defaultPadding = 20;

  static const double defaultRadius = 20;

  // ===========================================================================
  // Maps
  // ===========================================================================

  static const double defaultZoom = 16;

  static const double minZoom = 10;

  static const double maxZoom = 20;

  static const double driverSearchRadiusKm = 5;

  // ===========================================================================
  // Booking
  // ===========================================================================

  static const Duration bookingTimeout =
      Duration(seconds: 60);

  static const Duration driverLocationUpdateInterval =
      Duration(seconds: 10);

  // ===========================================================================
  // Upload
  // ===========================================================================

  static const int maxImageSizeMB = 10;

  // ===========================================================================
  // Pagination
  // ===========================================================================

  static const int pageSize = 20;

  // ===========================================================================
  // Validation
  // ===========================================================================

  static const int minimumPasswordLength = 8;

  static const int maxNameLength = 50;

  static const int maxPhoneLength = 11;
}