import 'package:flutter_riverpod/legacy.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../../data/models/route_policy_advisory.dart';

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
    this.additionalDropoffEnabled = false,
    this.additionalDestination,
    this.additionalDestinationName,
    this.additionalDestinationAddress,
    this.passengerNote = '',
    this.routePoints = const [],
    this.routeAdvisory = '',
    this.routePolicy = const RoutePolicyAdvisory(),
    this.distanceMeters = 0,
    this.duration = '',

    // Fare breakdown
    this.baseFare = 0,
    this.distanceFare = 0,
    this.additionalPassengerFee = 0,
    this.baggageFee = 0,
    this.boundarySurcharge = 0,
    this.additionalDropoffFare = 0,
    this.estimatedFare = 0,

    // Booking options
    this.additionalPassengers = 0,
    this.baggageCount = 0,
    this.isOutsideToda = false,

    this.goQuoteToken = '',
    this.goQuoteExpiresAt,

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

  /// Optional second and final drop-off. The original destination remains
  /// drop-off 1 so old single-stop flows continue to work unchanged.
  final bool additionalDropoffEnabled;
  final LatLng? additionalDestination;
  final String? additionalDestinationName;
  final String? additionalDestinationAddress;
  final String passengerNote;

  LatLng? get finalDestination => additionalDestination ?? destination;
  String? get finalDestinationName =>
      additionalDestinationName ?? destinationName;
  String? get finalDestinationAddress =>
      additionalDestinationAddress ?? destinationAddress;
  int get dropoffCount => additionalDestination == null ? 1 : 2;

  /// Decoded Google Routes polyline.
  final List<LatLng> routePoints;

  /// Persistent passenger-facing notice when a safe alternative was selected.
  final String routeAdvisory;
  final RoutePolicyAdvisory routePolicy;

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
  final double additionalDropoffFare;

  /// Estimated total fare.
  final double estimatedFare;

  /// Additional passengers.
  final int additionalPassengers;

  /// Number of baggage items.
  final int baggageCount;

  /// Whether the trip is outside the TODA boundary.
  final bool isOutsideToda;

  /// Opaque, short-lived token issued through the private Go quote gateway.
  final String goQuoteToken;
  final DateTime? goQuoteExpiresAt;

  /// True when pickup, destination, and route exist.
  final bool hasRoute;

  BookingSession copyWith({
    LatLng? pickup,
    String? pickupName,
    String? pickupAddress,
    LatLng? destination,
    String? destinationName,
    String? destinationAddress,
    bool? additionalDropoffEnabled,
    LatLng? additionalDestination,
    String? additionalDestinationName,
    String? additionalDestinationAddress,
    bool clearAdditionalDestination = false,
    String? passengerNote,
    List<LatLng>? routePoints,
    String? routeAdvisory,
    RoutePolicyAdvisory? routePolicy,
    int? distanceMeters,
    String? duration,

    double? baseFare,
    double? distanceFare,
    double? additionalPassengerFee,
    double? baggageFee,
    double? boundarySurcharge,
    double? additionalDropoffFare,
    double? estimatedFare,

    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,
    String? goQuoteToken,
    DateTime? goQuoteExpiresAt,
    bool clearGoQuoteExpiry = false,
    bool? hasRoute,
  }) {
    return BookingSession(
      pickup: pickup ?? this.pickup,
      pickupName: pickupName ?? this.pickupName,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      destination: destination ?? this.destination,
      destinationName: destinationName ?? this.destinationName,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      additionalDropoffEnabled:
          additionalDropoffEnabled ?? this.additionalDropoffEnabled,
      additionalDestination: clearAdditionalDestination
          ? null
          : additionalDestination ?? this.additionalDestination,
      additionalDestinationName: clearAdditionalDestination
          ? null
          : additionalDestinationName ?? this.additionalDestinationName,
      additionalDestinationAddress: clearAdditionalDestination
          ? null
          : additionalDestinationAddress ?? this.additionalDestinationAddress,
      passengerNote: passengerNote ?? this.passengerNote,
      routePoints: routePoints ?? this.routePoints,
      routeAdvisory: routeAdvisory ?? this.routeAdvisory,
      routePolicy: routePolicy ?? this.routePolicy,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      duration: duration ?? this.duration,

      baseFare: baseFare ?? this.baseFare,
      distanceFare: distanceFare ?? this.distanceFare,
      additionalPassengerFee:
          additionalPassengerFee ?? this.additionalPassengerFee,
      baggageFee: baggageFee ?? this.baggageFee,
      boundarySurcharge: boundarySurcharge ?? this.boundarySurcharge,
      additionalDropoffFare:
          additionalDropoffFare ?? this.additionalDropoffFare,
      estimatedFare: estimatedFare ?? this.estimatedFare,

      additionalPassengers: additionalPassengers ?? this.additionalPassengers,
      baggageCount: baggageCount ?? this.baggageCount,
      isOutsideToda: isOutsideToda ?? this.isOutsideToda,
      goQuoteToken: goQuoteToken ?? this.goQuoteToken,
      goQuoteExpiresAt: clearGoQuoteExpiry
          ? null
          : goQuoteExpiresAt ?? this.goQuoteExpiresAt,
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
      routePoints: const <LatLng>[],
      routeAdvisory: '',
      routePolicy: const RoutePolicyAdvisory(),
      distanceMeters: 0,
      duration: '',
      baseFare: 0,
      distanceFare: 0,
      additionalPassengerFee: 0,
      baggageFee: 0,
      boundarySurcharge: 0,
      additionalDropoffFare: 0,
      estimatedFare: 0,
      isOutsideToda: false,
      goQuoteToken: '',
      clearGoQuoteExpiry: true,
      hasRoute: false,
    );
  }

  void enableAdditionalDropoff() {
    state = state.copyWith(
      additionalDropoffEnabled: true,
      routePoints: const <LatLng>[],
      goQuoteToken: '',
      clearGoQuoteExpiry: true,
      hasRoute: false,
    );
  }

  void removeAdditionalDropoff() {
    state = state.copyWith(
      additionalDropoffEnabled: false,
      clearAdditionalDestination: true,
      additionalDropoffFare: 0,
      routePoints: const <LatLng>[],
      goQuoteToken: '',
      clearGoQuoteExpiry: true,
      hasRoute: false,
    );
  }

  void updateAdditionalDestination({
    required LatLng destination,
    required String destinationName,
    required String destinationAddress,
  }) {
    state = state.copyWith(
      additionalDropoffEnabled: true,
      additionalDestination: destination,
      additionalDestinationName: destinationName,
      additionalDestinationAddress: destinationAddress,
      routePoints: const <LatLng>[],
      goQuoteToken: '',
      clearGoQuoteExpiry: true,
      hasRoute: false,
    );
  }

  void updatePassengerNote(String value) {
    state = state.copyWith(passengerNote: value.trim());
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
      routePoints: const <LatLng>[],
      routeAdvisory: '',
      routePolicy: const RoutePolicyAdvisory(),
      distanceMeters: 0,
      duration: '',
      baseFare: 0,
      distanceFare: 0,
      additionalPassengerFee: 0,
      baggageFee: 0,
      boundarySurcharge: 0,
      estimatedFare: 0,
      isOutsideToda: false,
      goQuoteToken: '',
      clearGoQuoteExpiry: true,
      hasRoute: false,
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
