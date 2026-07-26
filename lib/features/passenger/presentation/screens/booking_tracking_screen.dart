import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../app/routes.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/report_repository.dart';
import '../../../../data/repositories/safety_repository.dart';

import '../../providers/booking_listener_provider.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/driver_location_listener_provider.dart';

import '../widgets/driver_information_card.dart';

import '../../../ride/tracking/widgets/ride_actions_card.dart';
import '../../../ride/tracking/widgets/ride_cancel_dialog.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../../ride/tracking/widgets/trip_information_card.dart';
import '../../../ride/tracking/widgets/trip_status_card.dart';
import '../../../ride/tracking/models/ride_participant_role.dart';
import '../../../ride/tracking/services/ride_marker_factory.dart';
import 'trip_receipt_screen.dart';

class BookingTrackingScreen extends ConsumerStatefulWidget {
  const BookingTrackingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingTrackingScreen> createState() =>
      _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends ConsumerState<BookingTrackingScreen> {
  //==========================================================================
  // Services
  //==========================================================================

  final NavigationService _navigation = NavigationService.instance;

  //==========================================================================
  // Google Map
  //==========================================================================

  GoogleMapController? _mapController;
  BitmapDescriptor? _driverMarkerIcon;

  //==========================================================================
  // Route
  //==========================================================================

  List<LatLng> _routePoints = [];
  String? _loadedRouteKey;
  String? _loadingRouteKey;
  String? _eta;
  String? _remainingDistance;

  //==========================================================================
  // Navigation
  //==========================================================================

  bool _hasNavigatedToReceipt = false;

  //==========================================================================
  // Helpers
  //==========================================================================

  bool _tripStarted(Booking booking) {
    return booking.status == BookingStatus.passengerOnBoard ||
        booking.status == BookingStatus.completed;
  }

  LatLng _routeDestination(Booking booking) {
    return _tripStarted(booking) ? booking.destination : booking.pickup;
  }

  void _navigateToReceipt(Booking booking) {
    if (_hasNavigatedToReceipt) {
      return;
    }

    if (booking.status != BookingStatus.completed) {
      return;
    }

    _hasNavigatedToReceipt = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TripReceiptScreen(bookingId: booking.bookingId),
        ),
      );
    });
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();
    _loadDriverMarker();
  }

  Future<void> _loadDriverMarker() async {
    try {
      final icon = await RideMarkerFactory.driverMarker();
      if (mounted) setState(() => _driverMarkerIcon = icon);
    } catch (_) {
      // The default teal marker remains available if an app asset is missing.
    }
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
    final destination = _routeDestination(booking);
    final routeKey =
        '${booking.status.name}:${destination.latitude}:${destination.longitude}';
    if ((_loadedRouteKey == routeKey && _routePoints.isNotEmpty) ||
        _loadingRouteKey == routeKey) {
      return;
    }

    _loadingRouteKey = routeKey;

    Map<String, dynamic>? route;
    try {
      route = await _navigation.computeTrafficRoute(
        origin: driverLocation,
        destination: destination,
      );
    } finally {
      _loadingRouteKey = null;
    }

    if (!mounted || route == null) {
      return;
    }
    final resolvedRoute = route;

    final encodedPolyline = _navigation.encodedPolyline(resolvedRoute);

    final points = _navigation.decodePolyline(encodedPolyline);

    setState(() {
      _routePoints = points;
      _loadedRouteKey = routeKey;
      _eta = _navigation.duration(resolvedRoute);
      _remainingDistance =
          '${_navigation.distanceKm(resolvedRoute).toStringAsFixed(1)} km away';
    });
  }

  Future<void> _cancelBooking(Booking booking) async {
    final result = await showDialog<RideCancellationResult>(
      context: context,
      builder: (_) => const RideCancelDialog(isDriver: false),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(bookingControllerProvider.notifier)
          .cancelBooking(
            booking.bookingId,
            reasonCode: result.reason.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]+'),
              '_',
            ),
            reasonDetail: result.comment,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel booking: $error')),
      );
    }
  }

  Future<void> _reportDriver(Booking booking) async {
    final user = AuthRepository().currentUser;
    if (user == null || booking.driverId == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ReportRideDialog(
        onSubmit: (category, details) => ReportRepository().create(
          bookingId: booking.bookingId,
          reporterId: user.uid,
          reportedUserId: booking.driverId!,
          category: category,
          details: details,
        ),
      ),
    );
  }

  Future<void> _triggerSos(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record an SOS incident?'),
        content: const Text(
          'VolTrike will save this ride and location snapshot for authorized '
          'admins. This development feature does not contact emergency '
          'services, so contact them directly if immediate help is needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SafetyRepository().triggerSos(booking.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS incident recorded for review.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not record SOS: $error')));
    }
  }

  Future<void> _confirmCashPaid(Booking booking) async {
    try {
      await BookingRepository().confirmCashPayment(
        bookingId: booking.bookingId,
        received: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash payment marked as paid.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not confirm payment: $error')),
      );
    }
  }

  //==========================================================================
  // Google Map
  //==========================================================================

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Future<void> _moveCamera(LatLng target) async {
    if (_mapController == null) {
      return;
    }

    await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
  }

  Future<void> _followDriver({
    required Booking booking,
    required LatLng? driverLocation,
  }) async {
    if (driverLocation == null) {
      return;
    }

    await _moveCamera(driverLocation);

    await _loadRoute(booking: booking, driverLocation: driverLocation);
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
          markerId: const MarkerId('driver'),
          position: driverLocation,
          anchor: const Offset(0.5, 0.5),
          icon:
              _driverMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: 'Driver'),
        ),
      );
    }

    markers.add(
      Marker(
        markerId: const MarkerId('pickup'),
        position: booking.pickup,
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
    );

    markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: booking.destination,
        infoWindow: const InfoWindow(title: 'Destination'),
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
        polylineId: const PolylineId('route'),
        points: _routePoints,
        width: 5,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingListenerProvider(widget.bookingId));

    return bookingAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),

      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: Center(child: Text(error.toString())),
      ),

      data: (booking) {
        if (booking == null) {
          return const Scaffold(
            body: Center(child: Text('Booking not found.')),
          );
        }

        _navigateToReceipt(booking);

        if (booking.driverId == null) {
          return const Scaffold(
            body: Center(child: Text('Waiting for driver assignment...')),
          );
        }

        final driverLocationAsync = ref.watch(
          driverLocationListenerProvider(booking.driverId!),
        );

        return driverLocationAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),

          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(title: const Text('Booking')),
            body: Center(child: Text(error.toString())),
          ),

          data: (driverLocation) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _followDriver(booking: booking, driverLocation: driverLocation);
            });

            return Scaffold(
              appBar: AppBar(title: const Text('Track Ride')),

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
                      markers: _buildMarkers(
                        booking: booking,
                        driverLocation: driverLocation,
                      ),
                      polylines: _buildPolylines(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TripStatusCard(
                      status: booking.status,
                      role: RideParticipantRole.passenger,
                      eta: _eta,
                      distance: _remainingDistance,
                    ),
                  ),

                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          DriverInformationCard(
                            driverName: booking.driverName ?? 'VolTrike driver',
                            vehicleNumber:
                                booking.vehicleNumber ?? 'Not available',
                            plateNumber: booking.plateNumber ?? 'Not available',
                            todaName: booking.todaName ?? 'Not available',
                            photoUrl: booking.driverPhotoUrl,
                            rating: booking.driverRating,
                          ),

                          const SizedBox(height: 16),

                          if (booking.status == BookingStatus.driverAssigned ||
                              booking.status == BookingStatus.driverArriving)
                            RideActionsCard(
                              onCancel: () => _cancelBooking(booking),
                              onSos: () => _triggerSos(booking),
                            ),

                          if (booking.status ==
                              BookingStatus.driverArriving) ...[
                            const SizedBox(height: 8),
                            StreamBuilder<String?>(
                              stream: BookingRepository().watchPickupPin(
                                passengerId: booking.passengerId,
                                bookingId: booking.bookingId,
                              ),
                              builder: (context, snapshot) => Card(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: ListTile(
                                  leading: const Icon(Icons.pin_outlined),
                                  title: const Text('Pickup PIN'),
                                  subtitle: const Text(
                                    'Tell this PIN only to your assigned driver.',
                                  ),
                                  trailing: Text(
                                    snapshot.data ?? '••••',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 4,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          if (booking.status == BookingStatus.passengerOnBoard)
                            RideActionsCard(
                              onCall: () => context.push(
                                AppRoutes.bookingVoiceCall,
                                extra: booking.bookingId,
                              ),
                              onMessage: () => context.push(
                                AppRoutes.bookingChat,
                                extra: {
                                  'bookingId': booking.bookingId,
                                  'members': [
                                    booking.passengerId,
                                    booking.driverId!,
                                  ],
                                },
                              ),
                              onReport: () => _reportDriver(booking),
                              onSos: () => _triggerSos(booking),
                            ),

                          if (booking.status ==
                              BookingStatus.passengerOnBoard) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: booking.passengerPaidAt == null
                                    ? () => _confirmCashPaid(booking)
                                    : null,
                                icon: const Icon(Icons.payments_outlined),
                                label: Text(
                                  booking.passengerPaidAt == null
                                      ? 'Confirm cash paid · '
                                            '₱${booking.amountDue.toStringAsFixed(2)}'
                                      : 'Cash payment confirmed',
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          TripInformationCard(
                            pickup: booking.pickupAddress,
                            destination: booking.destinationAddress,
                            distance:
                                '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                            duration: _eta ?? '--',
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
