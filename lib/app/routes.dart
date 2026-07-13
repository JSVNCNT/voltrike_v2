class AppRoutes {
  const AppRoutes._();

  //==========================================================================
  // Startup
  //==========================================================================

  static const String splash = '/';

  static const String intro = '/intro';

  //==========================================================================
  // Authentication
  //==========================================================================

  static const String login = '/login';

  static const String forgotPassword =
      '/forgot-password';

  static const String emailVerification =
      '/verify-email';

  //==========================================================================
  // Passenger Registration
  //==========================================================================

  static const String passengerRegister =
      '/register/passenger';

  static const String passengerRegisterSuccess =
      '/register/passenger/success';

  //==========================================================================
  // Driver Registration
  //==========================================================================

  static const String driverRegister =
      '/register/driver';

  static const String driverRegisterStep1 =
      '/register/driver/step-1';

  static const String driverRegisterStep2 =
      '/register/driver/step-2';

  static const String driverRegisterStep3 =
      '/register/driver/step-3';

  static const String uploadDocuments =
      '/register/driver/upload-documents';

  /// Driver has submitted registration and is awaiting approval.
  static const String driverUnderReview =
      '/driver/under-review';

  //==========================================================================
  // Passenger
  //==========================================================================

  static const String passengerHome =
      '/passenger';

  static const String passengerDashboard =
      '/passenger/dashboard';

  static const String passengerSettings =
      '/passenger/settings';

  static const String passengerProfile =
      '/passenger/profile';

  static const String passengerTripHistory =
      '/passenger/trips';

  //==========================================================================
  // Driver
  //==========================================================================

  static const String driverHome =
      '/driver';

  static const String driverDashboard =
      '/driver/dashboard';

  static const String driverSettings =
      '/driver/settings';

  static const String driverProfile =
      '/driver/profile';

  static const String driverTrips =
      '/driver/trips';

  //==========================================================================
  // Booking
  //==========================================================================

  static const String booking =
      '/booking';

  static const String bookingDetails =
      '/booking/details';

  static const String trip =
      '/trip';

  static const String tripDetails =
      '/trip/details';

  //==========================================================================
  // Common
  //==========================================================================

  static const String profile =
      '/profile';

  static const String settings =
      '/settings';

  static const String notifications =
      '/notifications';
}