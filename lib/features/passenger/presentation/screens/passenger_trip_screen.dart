import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../data/models/booking.dart';

import '../../providers/booking_listener_provider.dart';
import '../../providers/driver_location_listener_provider.dart';

/// ===========================================================================
/// Passenger Trip Screen
///
/// Active trip after the passenger has boarded.
///
/// Features
/// • Live driver tracking
/// • Destination marker
/// • Driver marker
/// • Route to destination
/// • Trip information
/// • Driver information
/// ===========================================================================
class PassengerTripScreen
    extends ConsumerStatefulWidget {
  const PassengerTripScreen({
    super.key,
    required this.bookingId,
  });

  final String bookingId;

  @override
  ConsumerState<PassengerTripScreen>
      createState() =>
          _PassengerTripScreenState();
}

class _PassengerTripScreenState
    extends ConsumerState<PassengerTripScreen> {
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
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      _loadRoute();
    });
  }

  //==========================================================================
  // Load Route
  //==========================================================================

  Future<void> _loadRoute() async {
    final booking = ref.read(
      bookingListenerProvider(
        widget.bookingId,
      ),
    );

    booking.whenData(
      (Booking? bookingData) async {
        if (bookingData == null) {
          return;
        }

        if (bookingData.driverId == null) {
          return;
        }

        final driverLocation =
            await ref.read(
          driverLocationListenerProvider(
            bookingData.driverId!,
          ).future,
        );

        if (driverLocation == null) {
          return;
        }

        final route =
            await _navigation
                .computeTrafficRoute(
          origin: driverLocation,
          destination:
              bookingData.destination,
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
      },
    );
  }

  //==========================================================================
  // Google Map
  //==========================================================================

  void _onMapCreated(
    GoogleMapController controller,
  ) {
    _mapController = controller;
  }

  //==========================================================================
  // Dispose
  //==========================================================================

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  //==========================================================================
  // UI
  //==========================================================================
    //==========================================================================
  // Markers
  //==========================================================================

  Set<Marker> _buildMarkers({
    required Booking booking,
    required LatLng? driverLocation,
  }) {
    return {
      Marker(
        markerId: const MarkerId(
          'destination',
        ),
        position: booking.destination,
        infoWindow: const InfoWindow(
          title: 'Destination',
        ),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueRed,
        ),
      ),

      if (driverLocation != null)
        Marker(
          markerId: const MarkerId(
            'driver',
          ),
          position: driverLocation,
          infoWindow: const InfoWindow(
            title: 'Driver',
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
    };
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
          'trip_route',
        ),
        points: _routePoints,
        width: 5,
      ),
    };
  }

  //==========================================================================
  // Camera
  //==========================================================================

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

  Future<void> _followDriver(
    LatLng? driverLocation,
  ) async {
    if (driverLocation == null) {
      return;
    }

    await _moveCamera(
      driverLocation,
    );
  }

  //==========================================================================
  // Status
  //==========================================================================

  String _statusText(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return 'Waiting';

      case BookingStatus.driverAssigned:
        return 'Driver Assigned';

      case BookingStatus.driverArriving:
        return 'Driver Arriving';

      case BookingStatus.passengerOnBoard:
        return 'Trip In Progress';

      case BookingStatus.completed:
        return 'Trip Completed';

      case BookingStatus.cancelled:
        return 'Trip Cancelled';
    }
  }

  Color _statusColor(
    BookingStatus status,
  ) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.orange;

      case BookingStatus.driverAssigned:
        return Colors.blue;

      case BookingStatus.driverArriving:
        return Colors.green;

      case BookingStatus.passengerOnBoard:
        return Colors.indigo;

      case BookingStatus.completed:
        return Colors.teal;

      case BookingStatus.cancelled:
        return Colors.red;
    }
  }

  //==========================================================================
  // Build
  //==========================================================================
    @override
  Widget build(
    BuildContext context,
  ) {
    final bookingAsync = ref.watch(
      bookingListenerProvider(
        widget.bookingId,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Passenger Trip',
        ),
      ),
      body: bookingAsync.when(
        loading: () {
          return const Center(
            child:
                CircularProgressIndicator(),
          );
        },
        error: (error, _) {
          return Center(
            child: Text(
              error.toString(),
            ),
          );
        },
        data: (Booking? booking) {
          if (booking == null) {
            return const Center(
              child: Text(
                'Trip not found.',
              ),
            );
          }

          if (booking.driverId == null) {
            return const Center(
              child: Text(
                'Driver unavailable.',
              ),
            );
          }

          final driverLocationAsync =
              ref.watch(
            driverLocationListenerProvider(
              booking.driverId!,
            ),
          );

          return driverLocationAsync.when(
            loading: () {
              return const Center(
                child:
                    CircularProgressIndicator(),
              );
            },
            error: (error, _) {
              return Center(
                child: Text(
                  error.toString(),
                ),
              );
            },
            data: (driverLocation) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) {
                _followDriver(
                  driverLocation,
                );
              });

              return Stack(
                children: [
                  //----------------------------------------------------------------
                  // Google Map
                  //----------------------------------------------------------------

                  GoogleMap(
                    onMapCreated:
                        _onMapCreated,
                    initialCameraPosition:
                        CameraPosition(
                      target:
                          booking.destination,
                      zoom: 15,
                    ),
                    myLocationEnabled:
                        true,
                    myLocationButtonEnabled:
                        true,
                    zoomControlsEnabled:
                        false,
                    markers:
                        _buildMarkers(
                      booking: booking,
                      driverLocation:
                          driverLocation,
                    ),
                    polylines:
                        _buildPolylines(),
                  ),

                  //----------------------------------------------------------------
                  // Status Card
                  //----------------------------------------------------------------

                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              _statusText(
                                booking
                                    .status,
                              ),
                              style:
                                  const TextStyle(
                                fontSize:
                                    18,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),

                            const SizedBox(
                              height: 8,
                            ),

                            Chip(
                              backgroundColor:
                                  _statusColor(
                                booking
                                    .status,
                              ),
                              label: Text(
                                booking
                                    .status
                                    .name,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors
                                          .white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  //----------------------------------------------------------------
                  // Trip Information
                  //----------------------------------------------------------------

                  Align(
                    alignment:
                        Alignment
                            .bottomCenter,
                    child: Card(
                      margin:
                          const EdgeInsets.all(
                        16,
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          20,
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            const Text(
                              'Trip Information',
                              style:
                                  TextStyle(
                                fontSize:
                                    18,
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),

                            const SizedBox(
                              height: 16,
                            ),

                            ListTile(
                              leading:
                                  const Icon(
                                Icons.flag,
                              ),
                              title:
                                  const Text(
                                'Destination',
                              ),
                              subtitle:
                                  Text(
                                booking
                                    .destinationAddress,
                              ),
                            ),

                            ListTile(
                              leading:
                                  const Icon(
                                Icons.route,
                              ),
                              title:
                                  const Text(
                                'Distance Remaining',
                              ),
                              subtitle:
                                  Text(
                                '${booking.distanceMeters} m',
                              ),
                            ),

                            ListTile(
                              leading:
                                  const Icon(
                                Icons
                                    .payments,
                              ),
                              title:
                                  const Text(
                                'Estimated Fare',
                              ),
                              subtitle:
                                  Text(
                                '₱${booking.estimatedFare.toStringAsFixed(2)}',
                              ),
                            ),

                            ListTile(
                              leading:
                                  const Icon(
                                Icons
                                    .schedule,
                              ),
                              title:
                                  const Text(
                                'ETA',
                              ),
                              subtitle:
                                  const Text(
                                'Calculating...',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}