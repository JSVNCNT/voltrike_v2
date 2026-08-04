class AppConfig {
  const AppConfig._();

  // ---------------------------------------------------------------------------
  // Application
  // ---------------------------------------------------------------------------

  static const String appName = 'VolTrike';

  static const String appTagline = 'Clean Community Mobility';

  static const String packageName = 'com.example.voltrike_v2';

  static const String version = '1.0.0';
  static const int clientProtocolVersion = 3;
  static const int bookingSchemaVersion = 2;
  static const int expectedFunctionsProtocolVersion = 4;

  static const bool isProduction = false;

  // ---------------------------------------------------------------------------
  // Branding
  // ---------------------------------------------------------------------------

  static const String fontFamily = 'Poppins';

  // ---------------------------------------------------------------------------
  // Splash
  // ---------------------------------------------------------------------------

  static const Duration minimumSplashDuration = Duration(seconds: 2);

  // ---------------------------------------------------------------------------
  // Animation
  // ---------------------------------------------------------------------------

  static const Duration fastAnimation = Duration(milliseconds: 150);

  static const Duration normalAnimation = Duration(milliseconds: 300);

  static const Duration slowAnimation = Duration(milliseconds: 500);

  // ---------------------------------------------------------------------------
  // Maps
  // ---------------------------------------------------------------------------

  static const double defaultMapZoom = 16.0;

  static const double driverSearchRadiusKm = 5.0;

  // ---------------------------------------------------------------------------
  // Booking
  // ---------------------------------------------------------------------------

  static const Duration bookingTimeout = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // Firestore
  // ---------------------------------------------------------------------------

  static const String usersCollection = 'users';

  static const String ridesCollection = 'rides';

  static const String driversCollection = 'drivers';

  static const String passengersCollection = 'passengers';

  static const String notificationsCollection = 'notifications';

  static const String ratingsCollection = 'ratings';

  static const String todosCollection = 'todas';

  static const String pricingCollection = 'pricing';

  static const String geofenceCollection = 'geofences';
}
