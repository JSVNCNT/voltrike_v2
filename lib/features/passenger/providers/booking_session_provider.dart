import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ===========================================================================
/// Booking Session
///
/// Temporary booking information before creating a Firestore booking.
///
/// Stores:
/// • Pickup
/// • Destination
/// • Route
/// • Fare
/// • Passenger booking options
/// ===========================================================================
class BookingSession {
  const BookingSession({
    this.pickup,
    this.pickupName,
    this.pickupAddress,
    this.destination,
    this.destinationName,
    this.destinationAddress,
    this.routePoints = const [],
    this.distanceMeters = 0,
    this.duration = '',

    // Fare breakdown
    this.baseFare = 0,
    this.distanceFare = 0,
    this.additionalPassengerFee = 0,
    this.baggageFee = 0,
    this.boundarySurcharge = 0,
    this.estimatedFare = 0,

    // Booking options
    this.additionalPassengers = 0,
    this.baggageCount = 0,
    this.isOutsideToda = false,

    this.hasRoute = false,
  });

  /// Pickup location selected by the passenger.
  final LatLng? pickup;

  /// Pickup place name.
  final String? pickupName;

  /// Readable formatted pickup address returned by Places.
  final String? pickupAddress;

  /// Destination location.
  final LatLng? destination;

  /// Destination place name.
  final String? destinationName;

  /// Readable formatted destination address returned by Places.
  final String? destinationAddress;

  /// Decoded Google Routes polyline.
  final List<LatLng> routePoints;

  /// Route distance in meters.
  final int distanceMeters;

  /// Example: "11 mins"
  final String duration;

  /// Base fare.
  final double baseFare;

  /// Distance charge.
  final double distanceFare;

  /// Additional passenger charge.
  final double additionalPassengerFee;

  /// Baggage charge.
  final double baggageFee;

  /// Outside TODA surcharge.
  final double boundarySurcharge;

  /// Estimated total fare.
  final double estimatedFare;

  /// Additional passengers.
  final int additionalPassengers;

  /// Number of baggage items.
  final int baggageCount;

  /// Whether the trip is outside the TODA boundary.
  final bool isOutsideToda;

  /// True when pickup, destination, and route exist.
  final bool hasRoute;

  BookingSession copyWith({
    LatLng? pickup,
    String? pickupName,
    String? pickupAddress,
    LatLng? destination,
    String? destinationName,
    String? destinationAddress,
    List<LatLng>? routePoints,
    int? distanceMeters,
    String? duration,

    double? baseFare,
    double? distanceFare,
    double? additionalPassengerFee,
    double? baggageFee,
    double? boundarySurcharge,
    double? estimatedFare,

    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,
    bool? hasRoute,
  }) {
    return BookingSession(
      pickup: pickup ?? this.pickup,
      pickupName: pickupName ?? this.pickupName,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destination: destination ?? this.destination,
      destinationName: destinationName ?? this.destinationName,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      routePoints: routePoints ?? this.routePoints,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      duration: duration ?? this.duration,

      baseFare: baseFare ?? this.baseFare,
      distanceFare: distanceFare ?? this.distanceFare,
      additionalPassengerFee:
          additionalPassengerFee ?? this.additionalPassengerFee,
      baggageFee: baggageFee ?? this.baggageFee,
      boundarySurcharge: boundarySurcharge ?? this.boundarySurcharge,
      estimatedFare: estimatedFare ?? this.estimatedFare,

      additionalPassengers: additionalPassengers ?? this.additionalPassengers,
      baggageCount: baggageCount ?? this.baggageCount,
      isOutsideToda: isOutsideToda ?? this.isOutsideToda,
      hasRoute: hasRoute ?? this.hasRoute,
    );
  }

  static const empty = BookingSession();
}

/// ===========================================================================
/// Booking Session Notifier
/// ===========================================================================
class BookingSessionNotifier extends StateNotifier<BookingSession> {
  BookingSessionNotifier() : super(const BookingSession());

  /// Replace the current session.
  void update(BookingSession session) {
    state = session;
  }

  /// Update only the pickup.
  void updatePickup({
    required LatLng pickup,
    required String pickupName,
    required String pickupAddress,
  }) {
    state = state.copyWith(
      pickup: pickup,
      pickupName: pickupName,
      pickupAddress: pickupAddress,
    );
  }

  /// Update only the destination.
  void updateDestination({
    required LatLng destination,
    required String destinationName,
    required String destinationAddress,
  }) {
    state = state.copyWith(
      destination: destination,
      destinationName: destinationName,
      destinationAddress: destinationAddress,
    );
  }

  /// Update the calculated route and fare.
  void updateRoute({
    required List<LatLng> routePoints,
    required int distanceMeters,
    required String duration,

    required double baseFare,
    required double distanceFare,
    required double additionalPassengerFee,
    required double baggageFee,
    required double boundarySurcharge,
    required double estimatedFare,
  }) {
    state = state.copyWith(
      routePoints: routePoints,
      distanceMeters: distanceMeters,
      duration: duration,

      baseFare: baseFare,
      distanceFare: distanceFare,
      additionalPassengerFee: additionalPassengerFee,
      baggageFee: baggageFee,
      boundarySurcharge: boundarySurcharge,
      estimatedFare: estimatedFare,

      hasRoute: true,
    );
  }

  /// Reset the booking session.
  void reset() {
    state = BookingSession.empty;
  }
}

/// ===========================================================================
/// Booking Session Provider
/// ===========================================================================
final bookingSessionProvider =
    StateNotifierProvider<BookingSessionNotifier, BookingSession>(
      (ref) => BookingSessionNotifier(),
    );
