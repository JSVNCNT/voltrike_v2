import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltrike_v2/features/driver/providers/driver_location_provider.dart';

import '../../../../data/models/booking.dart';

import '../../providers/driver_current_booking_provider.dart';
import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_navigation_provider.dart';

import '../widgets/passenger_information_card.dart';

import '../../../ride/tracking/widgets/trip_information_card.dart';
import '../../../ride/tracking/widgets/trip_status_card.dart';
import '../../../ride/tracking/models/ride_participant_role.dart';
import '../../../ride/tracking/models/ride_action.dart';
import '../../../ride/tracking/services/ride_action_service.dart';
import '../../../ride/tracking/widgets/ride_actions_card.dart';
import '../../../ride/tracking/widgets/ride_cancel_dialog.dart';
import '../../../ride/tracking/widgets/ride_primary_button.dart';
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
  String? _loadedRouteKey;
  String? _loadingRouteKey;

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

    final destination = _routeDestination(booking);
    final routeKey = '${booking.status.name}:${destination.latitude}:${destination.longitude}';
    if (_loadedRouteKey == routeKey || _loadingRouteKey == routeKey) return;
    _loadingRouteKey = routeKey;

    try {
      await ref
          .read(
            driverNavigationControllerProvider.notifier,
          )
          .loadRoute(
            origin: driverLocation,
            destination: destination,
          );
      _loadedRouteKey = routeKey;
    } finally {
      _loadingRouteKey = null;
    }
  }

  Future<void> _advanceRide(Booking booking) async {
    try {
      final controller = ref.read(driverBookingControllerProvider.notifier);
      switch (booking.status) {
        case BookingStatus.driverAssigned:
          await controller.arrived(booking);
          break;
        case BookingStatus.driverArriving:
          await controller.startTrip(booking);
          break;
        case BookingStatus.passengerOnBoard:
          await controller.completeTrip(booking);
          break;
        case BookingStatus.pending:
        case BookingStatus.completed:
        case BookingStatus.cancelled:
          return;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update trip: $error')),
      );
    }
  }

  Future<void> _cancelRide(Booking booking) async {
    final result = await showDialog<RideCancellationResult>(
      context: context,
      builder: (_) => const RideCancelDialog(isDriver: true),
    );
    if (result == null || !mounted) return;

    try {
      await ref.read(driverBookingControllerProvider.notifier).cancelTrip(booking);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel trip: $error')),
      );
    }
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
  final primaryAction = booking.status == BookingStatus.driverAssigned ||
          booking.status == BookingStatus.driverArriving ||
          booking.status == BookingStatus.passengerOnBoard
      ? RideActionService.driverPrimaryAction(booking.status)
      : RidePrimaryAction.none;

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
            role: RideParticipantRole.driver,
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

                if (booking.status == BookingStatus.driverAssigned &&
                    driverLocation != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _followDriver(
                        booking: booking,
                        driverLocation: driverLocation,
                      ),
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Navigate to Pickup'),
                    ),
                  ),

                if (booking.status == BookingStatus.driverAssigned ||
                    booking.status == BookingStatus.driverArriving) ...[
                  const SizedBox(height: 8),
                  RideActionsCard(
                    onCancel: () => _cancelRide(booking),
                  ),
                ],

                if (primaryAction != RidePrimaryAction.none) ...[
                  const SizedBox(height: 8),
                  RidePrimaryButton(
                    action: primaryAction,
                    onPressed: () => _advanceRide(booking),
                  ),
                ],

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
