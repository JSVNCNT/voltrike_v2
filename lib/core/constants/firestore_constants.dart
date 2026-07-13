class FirestoreConstants {
  const FirestoreConstants._();

  // ===========================================================================
  // Collections
  // ===========================================================================

  static const String users = 'users';

  static const String passengers = 'passengers';

  static const String drivers = 'drivers';

  static const String vehicles = 'vehicles';

  static const String bookings = 'bookings';

  static const String trips = 'trips';

  static const String fares = 'fares';

  static const String todas = 'todas';

  static const String notifications = 'notifications';

  static const String reviews = 'reviews';

  static const String settings = 'settings';

  static const String geofences = 'geofences';

  // ===========================================================================
  // Common Fields
  // ===========================================================================

  static const String uid = 'uid';

  static const String email = 'email';

  static const String role = 'role';

  static const String status = 'status';

  static const String createdAt = 'createdAt';

  static const String updatedAt = 'updatedAt';

  // ===========================================================================
  // User Fields
  // ===========================================================================

  static const String firstName = 'firstName';

  static const String middleName = 'middleName';

  static const String lastName = 'lastName';

  static const String fullName = 'fullName';

  static const String phoneNumber = 'phoneNumber';

  static const String profileImage = 'profileImage';

  // ===========================================================================
  // Driver Fields
  // ===========================================================================

  static const String todaId = 'todaId';

  static const String vehicleId = 'vehicleId';

  static const String driverStatus = 'driverStatus';

  static const String isOnline = 'isOnline';

  static const String currentLocation = 'currentLocation';

  static const String licenseNumber = 'licenseNumber';

  static const String licenseExpiry = 'licenseExpiry';

  static const String approvedAt = 'approvedAt';

  static const String approvedBy = 'approvedBy';

  static const String rating = 'rating';

  static const String completedTrips = 'completedTrips';

  static const String totalEarnings = 'totalEarnings';

  // ===========================================================================
  // Vehicle Fields
  // ===========================================================================

  static const String plateNumber = 'plateNumber';

  static const String vehicleType = 'vehicleType';

  static const String vehicleColor = 'vehicleColor';

  static const String vehicleModel = 'vehicleModel';

  // ===========================================================================
  // Booking / Trip Fields
  // ===========================================================================

  static const String passengerId = 'passengerId';

  static const String driverId = 'driverId';

  static const String bookingStatus = 'bookingStatus';

  static const String tripStatus = 'tripStatus';

  static const String pickup = 'pickup';

  static const String destination = 'destination';

  static const String distance = 'distance';

  static const String fare = 'fare';

  static const String bags = 'bags';

  static const String additionalPassengers =
      'additionalPassengers';

  // ===========================================================================
  // TODA
  // ===========================================================================

  static const String todaName = 'todaName';

  static const String adminUid = 'adminUid';

  static const String barangay = 'barangayCode';

  // ===========================================================================
  // Notification
  // ===========================================================================

  static const String title = 'title';

  static const String body = 'body';

  static const String read = 'read';
}