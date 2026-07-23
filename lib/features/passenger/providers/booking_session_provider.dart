import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ===========================================================================
/// Booking Session
///
/// Stores the temporary booking information while the passenger
/// is selecting a destination and before a booking is created.
///
/// This is NOT the Firestore booking.
///
/// Used by:
/// • PassengerHomeScreen
/// • MapView
/// • HomeBottomSheet
/// • FareCard
/// ===========================================================================
class BookingSession {
  const BookingSession({
    this.destination,
    this.destinationName,
    this.routePoints = const [],
    this.distanceMeters = 0,
    this.duration = '',
    this.estimatedFare = 0,
    this.additionalPassengers = 0,
    this.baggageCount = 0,
    this.isOutsideToda = false,
    this.hasRoute = false,
  });

  /// Destination marker position.
  final LatLng? destination;

  /// Destination name shown to the passenger.
  final String? destinationName;

  /// Decoded Google polyline.
  final List<LatLng> routePoints;

  /// Distance returned by Google Routes.
  final int distanceMeters;

  /// Example:
  /// "480s"
  final String duration;

  /// Total estimated fare.
  final double estimatedFare;

  /// Additional passengers excluding the booking passenger.
  final int additionalPassengers;

  /// Number of baggage items.
  final int baggageCount;

  /// Whether destination is outside the TODA boundary.
  final bool isOutsideToda;

  /// True when a valid route has been computed.
  final bool hasRoute;

  BookingSession copyWith({
    LatLng? destination,
    String? destinationName,
    List<LatLng>? routePoints,
    int? distanceMeters,
    String? duration,
    double? estimatedFare,
    int? additionalPassengers,
    int? baggageCount,
    bool? isOutsideToda,
    bool? hasRoute,
  }) {
    return BookingSession(
      destination: destination ?? this.destination,
      destinationName:
          destinationName ?? this.destinationName,
      routePoints:
          routePoints ?? this.routePoints,
      distanceMeters:
          distanceMeters ?? this.distanceMeters,
      duration: duration ?? this.duration,
      estimatedFare:
          estimatedFare ?? this.estimatedFare,
      additionalPassengers:
          additionalPassengers ??
              this.additionalPassengers,
      baggageCount:
          baggageCount ?? this.baggageCount,
      isOutsideToda:
          isOutsideToda ?? this.isOutsideToda,
      hasRoute:
          hasRoute ?? this.hasRoute,
    );
  }
}

/// ===========================================================================
/// Booking Session Notifier
/// ===========================================================================
class BookingSessionNotifier
    extends StateNotifier<BookingSession> {
  BookingSessionNotifier()
      : super(const BookingSession());

  /// Updates the current booking preview.
  void update(
    BookingSession session,
  ) {
    state = session;
  }

  /// Clears the current booking preview.
  void reset() {
    state = const BookingSession();
  }
}

/// ===========================================================================
/// Booking Session Provider
/// ===========================================================================
final bookingSessionProvider =
    StateNotifierProvider<
        BookingSessionNotifier,
        BookingSession>(
  (ref) => BookingSessionNotifier(),
);