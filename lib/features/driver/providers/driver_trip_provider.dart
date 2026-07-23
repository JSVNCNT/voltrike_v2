import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ===========================================================================
/// Driver Trip Status
///
/// Represents the driver's current trip lifecycle.
///
/// Used by:
/// • DriverHomeScreen
/// • DriverBottomSheet
/// • DriverMapView
/// • Passenger App
/// ===========================================================================
enum DriverTripStatus {
  idle,
  waitingBooking,
  bookingReceived,
  bookingAccepted,
  navigatingToPickup,
  arrived,
  passengerOnBoard,
  navigatingToDestination,
  completed,
  cancelled,
}

class DriverTripNotifier
    extends StateNotifier<DriverTripStatus> {
  DriverTripNotifier()
      : super(
          DriverTripStatus.idle,
        );

  void waitingBooking() =>
      state =
          DriverTripStatus.waitingBooking;

  void bookingReceived() =>
      state =
          DriverTripStatus.bookingReceived;

  void bookingAccepted() =>
      state =
          DriverTripStatus.bookingAccepted;

  void navigatingToPickup() =>
      state = DriverTripStatus
          .navigatingToPickup;

  void arrived() =>
      state =
          DriverTripStatus.arrived;

  void passengerOnBoard() =>
      state = DriverTripStatus
          .passengerOnBoard;

  void navigatingToDestination() =>
      state = DriverTripStatus
          .navigatingToDestination;

  void completed() =>
      state =
          DriverTripStatus.completed;

  void cancelled() =>
      state =
          DriverTripStatus.cancelled;

  void reset() =>
      state =
          DriverTripStatus.idle;
}

final driverTripProvider =
    StateNotifierProvider<
        DriverTripNotifier,
        DriverTripStatus>(
  (ref) =>
      DriverTripNotifier(),
);