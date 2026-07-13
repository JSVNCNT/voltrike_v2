class BookingConfig {
  const BookingConfig._();

  //==========================================================================
  // Booking
  //==========================================================================

  static const int bookingTimeoutSeconds =
      60;

  static const int driverResponseSeconds =
      30;

  //==========================================================================
  // Search
  //==========================================================================

  static const double searchRadiusKm = 5;

  static const int maxNearbyDrivers = 10;

  //==========================================================================
  // Passenger
  //==========================================================================

  static const int maxPassengers = 4;

  static const int maxBags = 10;
}