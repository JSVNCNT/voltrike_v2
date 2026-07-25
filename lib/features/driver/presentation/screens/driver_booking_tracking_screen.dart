import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltrike_v2/features/driver/providers/driver_location_provider.dart';

import '../../../../data/models/booking.dart';

import '../../providers/driver_current_booking_provider.dart';
import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_navigation_provider.dart';

import '../widgets/passenger_information_card.dart';

import '../../../ride/tracking/widgets/ride_actions_card.dart';
import '../../../ride/tracking/widgets/trip_information_card.dart';
import '../../../ride/tracking/widgets/trip_status_card.dart';
import '../../providers/passenger_listener_provider.dart';

class DriverBookingTrackingScreen extends ConsumerStatefulWidget {
  const DriverBookingTrackingScreen({
    super.key,
    this.bookingId,
  });

  final String? bookingId;

  @override
  ConsumerState<DriverBookingTrackingScreen> createState() =>
      _DriverBookingTrackingScreenState();
}

class _DriverBookingTrackingScreenState
    extends ConsumerState<DriverBookingTrackingScreen> {
  //==========================================================================
  // Google Map
  //==========================================================================

  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(driverBookingControllerProvider.notifier)
          .restoreCurrentBooking();
    });
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

    //==========================================================================
  // Helpers
  //==========================================================================

  bool _tripStarted(
    Booking booking,
  ) {
    return booking.status ==
            BookingStatus.passengerOnBoard ||
        booking.status ==
            BookingStatus.completed;
  }

  LatLng _routeDestination(
    Booking booking,
  ) {
    return _tripStarted(booking)
        ? booking.destination
        : booking.pickup;
  }

  //==========================================================================
  // Google Map
  //==========================================================================

  void _onMapCreated(
    GoogleMapController controller,
  ) {
    _mapController = controller;
  }

  Future<void> _moveCamera(
    LatLng target,
  ) async {
    if (_mapController == null) {
      return;
    }

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        target,
        16,
      ),
    );
  }

  Future<void> _followDriver({
    required Booking booking,
    required LatLng driverLocation,
  }) async {
    await _moveCamera(
      driverLocation,
    );

    await ref
        .read(
          driverNavigationControllerProvider.notifier,
        )
        .loadRoute(
          origin: driverLocation,
          destination: _routeDestination(
            booking,
          ),
        );
  }

    //==========================================================================
// Build
//==========================================================================

@override
Widget build(
  BuildContext context,
) {
  final booking = ref.watch(
    driverCurrentBookingProvider,
  );

  if (booking == null) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Current Trip',
        ),
      ),
      body: const Center(
        child: Text(
          'No active booking.',
        ),
      ),
    );
  }

  //==========================================================================
  // Providers
  //==========================================================================

  final navigation = ref.watch(
    driverNavigationControllerProvider,
  );

  final driverLocation = ref.watch(
    driverLocationProvider,
  );

  final passengerAsync = ref.watch(
    passengerListenerProvider(
      booking.passengerId,
    ),
  );

  //==========================================================================
  // Follow Driver
  //==========================================================================

  if (driverLocation != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) return;

        _followDriver(
          booking: booking,
          driverLocation: driverLocation,
        );
      },
    );
  }

  //==========================================================================
  // UI
  //==========================================================================

  return Scaffold(
    appBar: AppBar(
      title: const Text(
        'Current Trip',
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: GoogleMap(
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            initialCameraPosition: CameraPosition(
              target: booking.pickup,
              zoom: 15,
            ),
            markers: {
              if (driverLocation != null)
                Marker(
                  markerId: const MarkerId(
                    'driver',
                  ),
                  position: driverLocation,
                  infoWindow: const InfoWindow(
                    title: 'Driver',
                  ),
                ),
              Marker(
                markerId: const MarkerId(
                  'pickup',
                ),
                position: booking.pickup,
                infoWindow: const InfoWindow(
                  title: 'Pickup',
                ),
              ),
              Marker(
                markerId: const MarkerId(
                  'destination',
                ),
                position: booking.destination,
                infoWindow: const InfoWindow(
                  title: 'Destination',
                ),
              ),
            },
            polylines: {
              if (navigation.routePoints.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId(
                    'route',
                  ),
                  points: navigation.routePoints,
                  width: 5,
                ),
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(
            16,
          ),
          child: TripStatusCard(
            status: booking.status,
            eta: navigation.eta,
            distance: navigation.distance,
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16,
            ),
            child: Column(
              children: [
                passengerAsync.when(
                  loading: () => const PassengerInformationCard(
                    passengerName: 'Loading...',
                  ),
                  error: (error, stackTrace) =>
                      const PassengerInformationCard(
                    passengerName: 'Unknown Passenger',
                  ),
                  data: (passenger) {
                    return PassengerInformationCard(
                      passengerName:
                          passenger?.fullName ??
                              'Unknown Passenger',
                      photoUrl:
                          passenger?.profileImage,
                    );
                  },
                ),

                const SizedBox(
                  height: 16,
                ),

                RideActionsCard(
                  onCall: () {
                    // TODO:
                    // Navigate to Ride Call
                  },
                  onMessage: () {
                    // TODO:
                    // Navigate to Ride Chat
                  },
                  onReport: () {
                    // TODO:
                    // Report passenger
                  },
                ),

                const SizedBox(
                  height: 16,
                ),

                TripInformationCard(
                  pickup: booking.pickupAddress,
                  destination:
                      booking.destinationAddress,
                  distance:
                      '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                  duration:
                      navigation.duration ?? '--',
                  fare:
                      '₱${booking.estimatedFare.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}
