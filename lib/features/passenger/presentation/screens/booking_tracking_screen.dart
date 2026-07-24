import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../data/models/booking.dart';

import '../../providers/booking_listener_provider.dart';
import '../../providers/driver_location_listener_provider.dart';

import '../widgets/driver_information_card.dart';

import '../../../ride/tracking/widgets/ride_actions_card.dart';
import '../../../ride/tracking/widgets/trip_information_card.dart';
import '../../../ride/tracking/widgets/trip_status_card.dart';

class BookingTrackingScreen extends ConsumerStatefulWidget {
  const BookingTrackingScreen({
    super.key,
    required this.bookingId,
  });

  final String bookingId;

  @override
  ConsumerState<BookingTrackingScreen> createState() =>
      _BookingTrackingScreenState();
}

class _BookingTrackingScreenState
    extends ConsumerState<BookingTrackingScreen> {
  //==========================================================================
  // Services
  //==========================================================================

  final NavigationService _navigation =
      NavigationService.instance;

  //==========================================================================
  // Google Map
  //==========================================================================

  GoogleMapController? _mapController;

  //==========================================================================
  // Route
  //==========================================================================

  List<LatLng> _routePoints = [];

  //==========================================================================
  // Navigation
  //==========================================================================

  bool _hasNavigatedToRating = false;

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

  void _navigateToRating(
    Booking booking,
  ) {
    if (_hasNavigatedToRating) {
      return;
    }

    if (booking.status !=
        BookingStatus.completed) {
      return;
    }

    _hasNavigatedToRating = true;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      context.go(
        AppRoutes.rateDriver,
        extra: booking.bookingId,
      );
    });
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

    //==========================================================================
  // Route
  //==========================================================================

  Future<void> _loadRoute({
    required Booking booking,
    required LatLng driverLocation,
  }) async {
    final route =
        await _navigation.computeTrafficRoute(
      origin: driverLocation,
      destination: _routeDestination(
        booking,
      ),
    );

    if (!mounted || route == null) {
      return;
    }

    final encodedPolyline =
        _navigation.encodedPolyline(
      route,
    );

    final points =
        _navigation.decodePolyline(
      encodedPolyline,
    );

    setState(() {
      _routePoints = points;
    });
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
    required LatLng? driverLocation,
  }) async {
    if (driverLocation == null) {
      return;
    }

    await _moveCamera(
      driverLocation,
    );

    await _loadRoute(
      booking: booking,
      driverLocation: driverLocation,
    );
  }

  //==========================================================================
  // Markers
  //==========================================================================

  Set<Marker> _buildMarkers({
    required Booking booking,
    required LatLng? driverLocation,
  }) {
    final markers = <Marker>{};

    if (driverLocation != null) {
      markers.add(
        Marker(
          markerId:
              const MarkerId(
            'driver',
          ),
          position: driverLocation,
          infoWindow:
              const InfoWindow(
            title: 'Driver',
          ),
        ),
      );
    }

    markers.add(
      Marker(
        markerId:
            const MarkerId(
          'pickup',
        ),
        position: booking.pickup,
        infoWindow:
            const InfoWindow(
          title: 'Pickup',
        ),
      ),
    );

    markers.add(
      Marker(
        markerId:
            const MarkerId(
          'destination',
        ),
        position:
            booking.destination,
        infoWindow:
            const InfoWindow(
          title: 'Destination',
        ),
      ),
    );

    return markers;
  }

  //==========================================================================
  // Polylines
  //==========================================================================

  Set<Polyline> _buildPolylines() {
    if (_routePoints.isEmpty) {
      return {};
    }

    return {
      Polyline(
        polylineId:
            const PolylineId(
          'route',
        ),
        points: _routePoints,
        width: 5,
      ),
    };
  }

    @override
  Widget build(
    BuildContext context,
  ) {
    final bookingAsync = ref.watch(
      bookingListenerProvider(
        widget.bookingId,
      ),
    );

    return bookingAsync.when(
      loading: () => const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      ),

      error: (
        error,
        stackTrace,
      ) =>
          Scaffold(
        appBar: AppBar(
          title: const Text(
            'Booking',
          ),
        ),
        body: Center(
          child: Text(
            error.toString(),
          ),
        ),
      ),

      data: (booking) {
        if (booking == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Booking not found.',
              ),
            ),
          );
        }

        _navigateToRating(
          booking,
        );

        if (booking.driverId == null) {
  return const Scaffold(
    body: Center(
      child: Text(
        'Waiting for driver assignment...',
      ),
    ),
  );
}

final driverLocationAsync = ref.watch(
  driverLocationListenerProvider(
    booking.driverId!,
  ),
);

        return driverLocationAsync.when(
          loading: () => const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          ),

          error: (
            error,
            stackTrace,
          ) =>
              Scaffold(
            appBar: AppBar(
              title: const Text(
                'Booking',
              ),
            ),
            body: Center(
              child: Text(
                error.toString(),
              ),
            ),
          ),

          data: (
            driverLocation,
          ) {
            WidgetsBinding.instance
                .addPostFrameCallback(
              (_) {
                _followDriver(
                  booking: booking,
                  driverLocation:
                      driverLocation,
                );
              },
            );

            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Track Ride',
                ),
              ),

              body: Column(
                children: [
                  Expanded(
                    child: GoogleMap(
                      onMapCreated:
                          _onMapCreated,
                      myLocationEnabled:
                          true,
                      myLocationButtonEnabled:
                          true,
                      initialCameraPosition:
                          CameraPosition(
                        target:
                            booking.pickup,
                        zoom: 15,
                      ),
                      markers:
                          _buildMarkers(
                        booking: booking,
                        driverLocation:
                            driverLocation,
                      ),
                      polylines:
                          _buildPolylines(),
                    ),
                  ),

                  Padding(
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    child:
                        TripStatusCard(
                      status:
                          booking.status,
                      eta: null,
                      distance: null,
                    ),
                  ),

                                    SingleChildScrollView(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      child: Column(
                        children: [
                          DriverInformationCard(
    driverName: booking.driverName ?? 'Unknown Driver',
    vehicleNumber: booking.vehicleNumber ?? '-',
    plateNumber: booking.plateNumber ?? '-',
    todaName: booking.todaName ?? '-',
    rating: booking.driverRating,
),

                          const SizedBox(
                            height: 16,
                          ),

                          RideActionsCard(
                            onCall: () {
                              // TODO:
                              // Call driver
                            },
                            onMessage: () {
                              // TODO:
                              // Message driver
                            },
                            onReport: () {
                              // TODO:
                              // Report driver
                            },
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          TripInformationCard(
                            pickup: booking
                                .pickupAddress,
                            destination: booking
                                .destinationAddress,
                            distance:
                                '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                            duration:
                                '--',
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
          },
        );
      },
    );
  }

    }
    