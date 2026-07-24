import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltrike_v2/app/routes.dart';

import '../../../../core/services/navigation_service.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';

import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_booking_listener_provider.dart';
import '../../providers/driver_current_booking_provider.dart';
import '../../providers/driver_incoming_booking_provider.dart';
import '../../providers/driver_location_controller_provider.dart';
import '../../providers/driver_location_provider.dart';
import '../../providers/driver_status_provider.dart';
import '../../providers/driver_trip_provider.dart';
import '../../providers/driver_current_booking_listener_provider.dart';

import '../widgets/booking_request_card.dart';
import '../widgets/driver_bottom_sheet.dart';
import '../widgets/driver_map_view.dart';


/// ===========================================================================
/// Driver Home Screen
///
/// Responsibilities
/// • Driver GPS
/// • Driver Availability
/// • Receive Bookings
/// • Navigation
/// • Trip Lifecycle
/// ===========================================================================
class DriverHomeScreen
    extends ConsumerStatefulWidget {
  const DriverHomeScreen({
    super.key,
  });

  @override
  ConsumerState<DriverHomeScreen>
      createState() =>
          _DriverHomeScreenState();
}

class _DriverHomeScreenState
    extends ConsumerState<DriverHomeScreen> {
  //==========================================================================
  // Navigation
  //==========================================================================

  final NavigationService _navigation =
      NavigationService.instance;

  GoogleMapController?
      _mapController;

  //==========================================================================
  // Route
  //==========================================================================

  List<LatLng> _routePoints = [];


  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      _initializeDriver();
    });
  }

  Future<void>
      _initializeDriver() async {
    await ref
        .read(
          driverLocationControllerProvider
              .notifier,
        )
        .stopTracking();
  }

  //==========================================================================
  // Online / Offline
  //==========================================================================

  Future<void> _toggleOnline(
    bool online,
  ) async {
    final statusNotifier =
        ref.read(
      driverStatusProvider.notifier,
    );

    final bookingController =
        ref.read(
      driverBookingControllerProvider
          .notifier,
    );

    final locationController =
        ref.read(
      driverLocationControllerProvider
          .notifier,
    );

    final bookingListener =
        ref.read(
      driverBookingListenerProvider,
    );

    if (online) {
      statusNotifier.goOnline();

      await bookingController.goOnline();

      await locationController
          .startTracking();

      bookingListener.startListening();
    } else {
      statusNotifier.goOffline();

      await bookingListener
          .stopListening();

      await locationController
          .stopTracking();

      await bookingController
          .goOffline();

      setState(() {
        _routePoints.clear();
      });
    }
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  @override
void dispose() {
  _navigation.dispose();
  _mapController?.dispose();

  super.dispose();
}

 //==========================================================================
// Driver Actions
//==========================================================================

Future<void> _acceptBooking() async {
  final booking = ref.read(
    driverIncomingBookingProvider,
  );

  if (booking == null) {
    return;
  }

  await ref
      .read(
        driverBookingControllerProvider.notifier,
      )
      .acceptBooking(
        booking,
      );

  // Start listening to the accepted booking.
  ref
      .read(
        driverCurrentBookingListenerProvider,
      )
      .startListening(
        booking.bookingId,
      );

  // Remove the pending booking.
  ref
      .read(
        driverIncomingBookingProvider.notifier,
      )
      .clearBooking();

  ref
      .read(
        driverTripProvider.notifier,
      )
      .bookingAccepted();

  if (!mounted) {
    return;
  }

  context.go(
    AppRoutes.driverBookingTracking,
  );
}

Future<void> _declineBooking() async {
  final booking = ref.read(
    driverIncomingBookingProvider,
  );

  if (booking == null) {
    return;
  }

  await ref
      .read(
        driverBookingControllerProvider.notifier,
      )
      .declineBooking(
        booking,
      );

  ref
      .read(
        driverIncomingBookingProvider.notifier,
      )
      .clearBooking();

  ref
      .read(
        driverTripProvider.notifier,
      )
      .waitingBooking();

  if (mounted) {
    setState(() {
      _routePoints.clear();
    });
  }

  if (!mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Booking declined.',
      ),
    ),
  );
}

  //==========================================================================
  // Navigation
  //==========================================================================

  Future<void> _navigateToPickup() async {
    final booking = ref.read(
      driverCurrentBookingProvider,
    );

    final driverLocation = ref.read(
      driverLocationProvider,
    );

    if (booking == null ||
        driverLocation == null) {
      return;
    }

    final route =
        await _navigation
            .computeTrafficRoute(
      origin: driverLocation,
      destination: booking.pickup,
    );

    if (route == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _routePoints =
          _navigation.decodePolyline(
        _navigation.encodedPolyline(
          route,
        ),
      );
    });

    ref
        .read(
          driverTripProvider.notifier,
        )
        .navigatingToPickup();
  }

  Future<void>
      _navigateToDestination() async {
    final booking = ref.read(
      driverCurrentBookingProvider,
    );

    final driverLocation = ref.read(
      driverLocationProvider,
    );

    if (booking == null ||
        driverLocation == null) {
      return;
    }

    final route =
        await _navigation
            .computeTrafficRoute(
      origin: driverLocation,
      destination:
          booking.destination,
    );

    if (route == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _routePoints =
          _navigation.decodePolyline(
        _navigation.encodedPolyline(
          route,
        ),
      );
    });

    ref
        .read(
          driverTripProvider.notifier,
        )
        .navigatingToDestination();
  }

  //==========================================================================
  // Trip Lifecycle
  //==========================================================================

    Future<void> _arrived() async {
    final booking = ref.read(
      driverCurrentBookingProvider,
    );

    if (booking == null) {
      return;
    }

    await ref
        .read(
          driverBookingControllerProvider
              .notifier,
        )
        .arrived(
          booking,
        );

    ref
        .read(
          driverTripProvider.notifier,
        )
        .arrived();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Passenger pickup reached.',
        ),
      ),
    );
  }

  Future<void> _startTrip() async {
    final booking = ref.read(
      driverCurrentBookingProvider,
    );

    if (booking == null) {
      return;
    }

    await ref
        .read(
          driverBookingControllerProvider
              .notifier,
        )
        .startTrip(
          booking,
        );

    ref
        .read(
          driverTripProvider.notifier,
        )
        .passengerOnBoard();

    await _navigateToDestination();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Trip started.',
        ),
      ),
    );
  }

  Future<void> _completeTrip() async {
    final booking = ref.read(
      driverCurrentBookingProvider,
    );

    if (booking == null) {
      return;
    }

    await ref
        .read(
          driverBookingControllerProvider
              .notifier,
        )
        .completeTrip(
          booking,
        );

        if (!mounted) {
  return;
}

context.go(
  AppRoutes.driverHome,
);

    ref
        .read(
          driverCurrentBookingProvider
              .notifier,
        )
        .clearBooking();

    ref
        .read(
          driverTripProvider.notifier,
        )
        .completed();

    if (mounted) {
      setState(() {
        _routePoints.clear();
      });
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Trip completed.',
        ),
      ),
    );
  }

  //==========================================================================
// UI
//==========================================================================

@override
Widget build(
  BuildContext context,
) {
  final incomingBooking = ref.watch(
    driverIncomingBookingProvider,
  );

  final currentBooking = ref.watch(
    driverCurrentBookingProvider,
  );

  final driverLocation = ref.watch(
    driverLocationProvider,
  );

  final driverStatus = ref.watch(
    driverStatusProvider,
  );

  final tripStatus = ref.watch(
    driverTripProvider,
  );

  final hasIncomingBooking =
      incomingBooking != null;

  final hasCurrentBooking =
      currentBooking != null;

  // Booking shown in the bottom sheet.
  // Before acceptance -> incoming booking.
  // After acceptance -> active booking.
  final displayBooking =
      currentBooking ?? incomingBooking;

  return Scaffold(
    appBar: const AppAppBar(
      title: 'Driver',
      showNotifications: true,
    ),
    body: Stack(
      children: [
        //------------------------------------------------------------------
        // Map
        //------------------------------------------------------------------

        Positioned.fill(
          child: DriverMapView(
            driverLocation:
                driverLocation,
            pickupLocation:
                currentBooking?.pickup,
            destinationLocation:
                currentBooking?.destination,
            routePoints:
                _routePoints,
          ),
        ),

          //------------------------------------------------------------------
          // Incoming Booking Card
          //------------------------------------------------------------------

                    if (hasIncomingBooking &&
              tripStatus ==
                  DriverTripStatus.bookingReceived)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: BookingRequestCard(
                passengerName:
                    incomingBooking.passengerId,
                pickupAddress:
                    incomingBooking.pickupAddress,
                destinationAddress:
                    incomingBooking.destinationAddress,
                estimatedFare:
                    '₱${incomingBooking.estimatedFare.toStringAsFixed(2)}',
                distance:
                    '${incomingBooking.distanceMeters} m',
                onAccept: _acceptBooking,
                onDecline: _declineBooking,
              ),
            ),
          //------------------------------------------------------------------
          // Bottom Sheet
          //------------------------------------------------------------------

          Align(
            alignment:
                Alignment.bottomCenter,
            child: DriverBottomSheet(
              isOnline:
                  driverStatus !=
                      DriverStatus.offline,

              passengerName:
                  displayBooking?.passengerId,

              pickupAddress:
                  displayBooking?.pickupAddress,

              destinationAddress:
                  displayBooking?.destinationAddress,

              estimatedFare:
                  displayBooking == null
                      ? null
                      : '₱${displayBooking.estimatedFare.toStringAsFixed(2)}',

              distance:
                  displayBooking == null
                      ? null
                      : '${displayBooking.distanceMeters} m',

              onOnlineChanged:
                  _toggleOnline,

              onAcceptBooking:
                  hasIncomingBooking
                      ? _acceptBooking
                      : null,

              onDeclineBooking:
                  hasIncomingBooking
                      ? _declineBooking
                      : null,

              onNavigate:
                  hasCurrentBooking
                      ? _navigateToPickup
                      : null,

              onArrived:
                  hasCurrentBooking
                      ? _arrived
                      : null,

              onStartTrip:
                  hasCurrentBooking
                      ? _startTrip
                      : null,

              onCompleteTrip:
                  hasCurrentBooking
                      ? _completeTrip
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}