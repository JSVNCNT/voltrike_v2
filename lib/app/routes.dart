class AppRoutes {
  const AppRoutes._();

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------

  static const String splash = '/';
  static const String landing = '/landing';

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  static const String login = '/login';

  static const String passengerRegister =
      '/register/passenger';

  static const String driverRegister =
      '/register/driver';

  static const String forgotPassword =
      '/forgot-password';

  // ---------------------------------------------------------------------------
  // Passenger
  // ---------------------------------------------------------------------------

  static const String passengerHome =
      '/passenger';

  static const String passengerDashboard =
      '/passenger/dashboard';

  static const String passengerSettings =
      '/passenger/settings';

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------

  static const String driverHome =
      '/driver';

  static const String driverDashboard =
      '/driver/dashboard';

  static const String driverSettings =
      '/driver/settings';

  // ---------------------------------------------------------------------------
  // Booking
  // ---------------------------------------------------------------------------

  static const String booking =
      '/booking';

  static const String trip =
      '/trip';

  // ---------------------------------------------------------------------------
  // Common
  // ---------------------------------------------------------------------------

  static const String profile =
      '/profile';
}