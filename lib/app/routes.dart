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

  static const String driverUnderReview =
      '/driver/under-review';

  //==========================================================================
  // Passenger
  //==========================================================================

  /// Passenger shell
  static const String passengerHome =
      '/passenger';

  static const String passengerDashboard =
      '/passenger/dashboard';

  static const String passengerProfile =
      '/passenger/profile';

  static const String passengerTripHistory =
      '/passenger/trips';

  static const String passengerSettings =
      '/passenger/settings';

      static const String editPassengerProfile =
    '/passenger/edit-profile';



  //==========================================================================
  // Passenger Booking Flow
  //==========================================================================

  static const String searchingDriver =
      '/passenger/searching-driver';

  static const String driverTracking =
      '/passenger/driver-tracking';

  static const String passengerTrip =
      '/passenger/trip';

  static const String rateDriver =
      '/passenger/rate-driver';

  static const String passengerReceipt =
      '/passenger/trip-receipt';

  //==========================================================================
// Driver
//==========================================================================

/// Driver home
static const String driverHome =
    '/driver';

static const driverBookingTracking =
'/driver/booking-tracking';

static const String driverReceipt =
    '/driver/trip-receipt';

static const String driverDashboard =
    '/driver/dashboard';

static const String driverProfile =
    '/driver/profile';

static const String editDriverProfile =
    '/driver/edit-profile';

static const String driverTripHistory =
    '/driver/trips';

static const String driverEarnings =
    '/driver/earnings';

static const String driverSettings =
    '/driver/settings';

static const String aboutVoltrike =
    '/driver/aboutVoltrike';

static const String privacyPolicy =
    '/driver/privacy-policy';

static const String termsAndConditions =
    '/driver/termsAndConditions';
  //==========================================================================
  // Driver Booking Flow
  //==========================================================================

  static const String currentBooking =
      '/driver/current-booking';

  //==========================================================================
  // Booking
  //==========================================================================

  static const String booking =
      '/booking';

  static const String bookingDetails =
      '/booking/details';

  //==========================================================================
  // Trip
  //==========================================================================

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

  static const String bookingChat = '/ride/chat';

  static const String bookingVoiceCall = '/ride/voice-call';

  static const String incomingBookingCall = '/ride/incoming-call';

  //==========================================================================
  // Future
  //==========================================================================

  static const String adminDashboard =
      '/admin/dashboard';

  static const String todaManagement =
      '/admin/todas';

  static const String userManagement =
      '/admin/users';

  static const String reports =
      '/admin/reports';
}
