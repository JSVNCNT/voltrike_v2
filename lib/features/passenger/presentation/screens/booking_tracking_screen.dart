import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../app/routes.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/chat_repository.dart';
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
import '../../../ride/tracking/services/route_refresh_policy.dart';
import '../../../ride/tracking/services/ride_stage_presentation_service.dart';
import '../../../ride/chat/ride_chat_alert_listener.dart';
import '../../../ride/routing/booking_route_coordinator.dart';
import '../../../ride/routing/booking_route_resolver.dart';

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
  final RouteRefreshPolicy _routeRefreshPolicy = RouteRefreshPolicy();
  String? _eta;
  String? _remainingDistance;
  String? _routeWarning;

  //==========================================================================
  // Navigation
  //==========================================================================

  ProviderSubscription<AsyncValue<Booking?>>? _bookingSubscription;
  BookingStatus? _lastRoutedStatus;
  bool _sosSubmitting = false;

  //==========================================================================
  // Helpers
  //==========================================================================

  bool _tripStarted(Booking booking) {
    return booking.status == BookingStatus.passengerOnBoard ||
        booking.status == BookingStatus.paymentConfirmation ||
        booking.status == BookingStatus.completed;
  }

  LatLng _routeDestination(Booking booking) {
    return _tripStarted(booking) ? booking.destination : booking.pickup;
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();
    _loadDriverMarker();
    _bookingSubscription = ref.listenManual<AsyncValue<Booking?>>(
      bookingListenerProvider(widget.bookingId),
      (_, next) => next.whenData(_handleBookingRoute),
    );
  }

  void _handleBookingRoute(Booking? booking) {
    if (booking == null || _lastRoutedStatus == booking.status) return;
    _lastRoutedStatus = booking.status;
    if (booking.status != BookingStatus.completed &&
        booking.status != BookingStatus.cancelled &&
        booking.status != BookingStatus.pending) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      BookingRouteCoordinator.open(
        context,
        role: BookingParticipantRole.passenger,
        booking: booking,
      );
    });
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
    _bookingSubscription?.close();
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
    if (!_routeRefreshPolicy.shouldRefresh(
      origin: driverLocation,
      destination: destination,
      hasRoute: _routePoints.isNotEmpty,
    )) {
      return;
    }
    _routeRefreshPolicy.begin();

    Map<String, dynamic>? route;
    try {
      route = await _navigation.computeTrafficRoute(
        origin: driverLocation,
        destination: destination,
      );
    } catch (_) {
      _routeRefreshPolicy.fail();
      if (mounted) {
        setState(() {
          _routeWarning = 'Live route is temporarily unavailable.';
        });
      }
      return;
    }

    if (!mounted || route == null) {
      _routeRefreshPolicy.fail();
      if (mounted) {
        setState(() {
          _routeWarning = 'Waiting for an updated driver route.';
        });
      }
      return;
    }
    final resolvedRoute = route;

    final encodedPolyline = _navigation.encodedPolyline(resolvedRoute);

    final points = _navigation.decodePolyline(encodedPolyline);

    setState(() {
      _routePoints = points;
      _eta = _navigation.duration(resolvedRoute);
      _remainingDistance =
          '${_navigation.distanceKm(resolvedRoute).toStringAsFixed(1)} km away';
      _routeWarning = null;
    });
    _routeRefreshPolicy.succeed(
      origin: driverLocation,
      destination: destination,
    );
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
      if (mounted) {
        context.go(AppRoutes.passengerHome);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel booking: $error')),
      );
    }
  }

  void _openCall(Booking booking) {
    context.push(AppRoutes.bookingVoiceCall, extra: booking.bookingId);
  }

  void _openChat(Booking booking) {
    context.push(
      AppRoutes.bookingChat,
      extra: {
        'bookingId': booking.bookingId,
        'members': [booking.passengerId, booking.driverId!],
      },
    );
  }

  Widget _passengerNavigation([Booking? activeBooking]) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        const routes = [
          AppRoutes.passengerHome,
          AppRoutes.passengerDashboard,
          AppRoutes.passengerTripHistory,
          AppRoutes.passengerProfile,
        ];
        if (index == 0 && activeBooking != null) {
          context.go(AppRoutes.driverTracking, extra: activeBooking.bookingId);
          return;
        }
        context.go(routes[index]);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Trips',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _activeRideActions(Booking booking) {
    final stage = RideStagePresentationService.resolve(
      role: RideParticipantRole.passenger,
      status: booking.status,
    );
    final userId = AuthRepository().currentUser?.uid;
    return StreamBuilder<int>(
      stream: userId == null
          ? Stream<int>.value(0)
          : ChatRepository().unreadCount(
              bookingId: booking.bookingId,
              userId: userId,
            ),
      builder: (context, snapshot) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: RideActionsCard(
          onCall: stage.allowContact ? () => _openCall(booking) : null,
          onMessage: stage.allowContact ? () => _openChat(booking) : null,
          onCancel: stage.allowCancel ? () => _cancelBooking(booking) : null,
          onReport: stage.allowReport ? () => _reportDriver(booking) : null,
          onSos: stage.allowSos && !_sosSubmitting
              ? () => _triggerSos(booking)
              : null,
          messageBadge: snapshot.data ?? 0,
        ),
      ),
    );
  }

  Future<void> _reportDriver(Booking booking) async {
    if (booking.driverId == null) return;
    await showRideReportDialog(
      context: context,
      booking: booking,
      reporterIsDriver: false,
    );
  }

  Future<void> _triggerSos(Booking booking) async {
    if (_sosSubmitting) return;
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
    if (confirmed != true || !mounted) return;
    setState(() => _sosSubmitting = true);
    try {
      final alreadyRecorded = await SafetyRepository().triggerSos(
        booking.bookingId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyRecorded
                ? 'This SOS incident is already recorded for review.'
                : 'SOS incident recorded for review.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not record SOS: $error')));
    } finally {
      if (mounted) setState(() => _sosSubmitting = false);
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

  Widget _trackingSheet({
    required Booking booking,
    required ScrollController scrollController,
  }) {
    return Material(
      elevation: 10,
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TripStatusCard(
                  status: booking.status,
                  role: RideParticipantRole.passenger,
                  eta: _eta,
                  distance: _remainingDistance,
                ),
                if (_routeWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _routeWarning!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                DriverInformationCard(
                  driverName: booking.driverName ?? 'VolTrike driver',
                  vehicleNumber: booking.vehicleNumber ?? 'Not available',
                  plateNumber: booking.plateNumber ?? 'Not available',
                  todaName: booking.todaName ?? 'Not available',
                  photoUrl: booking.driverPhotoUrl,
                  rating: booking.driverRating,
                ),
                const SizedBox(height: 10),
                _activeRideActions(booking),
                const SizedBox(height: 10),
                TripInformationCard(
                  pickup: booking.pickupAddress,
                  destination: booking.destinationAddress,
                  distance:
                      '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                  duration: _eta ?? '--',
                  fare: '₱${booking.estimatedFare.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),
          if (RideStagePresentationService.resolve(
            role: RideParticipantRole.passenger,
            status: booking.status,
          ).allowContact)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openCall(booking),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _openChat(booking),
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('Message'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(bookingListenerProvider(widget.bookingId));

    return bookingAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),

      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: Center(child: Text(DomainErrorMapper.message(error))),
      ),

      data: (booking) {
        if (booking == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Booking unavailable')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'This booking is no longer available.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.passengerHome),
                      child: const Text('Back to home'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (booking.driverId == null) {
          final cancelled = booking.status == BookingStatus.cancelled;
          return Scaffold(
            appBar: AppBar(
              title: Text(cancelled ? 'Booking cancelled' : 'Finding a driver'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cancelled ? Icons.cancel_outlined : Icons.search,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      cancelled
                          ? 'This booking was cancelled.'
                          : 'Waiting for a driver assignment...',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.passengerHome),
                      child: Text(
                        cancelled ? 'Book another ride' : 'Back to home',
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            body: Center(child: Text(DomainErrorMapper.message(error))),
          ),

          data: (driverLocation) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _followDriver(booking: booking, driverLocation: driverLocation);
            });

            return Scaffold(
              appBar: AppBar(title: const Text('Track Ride')),
              bottomNavigationBar: _passengerNavigation(booking),
              body: RideChatAlertListener(
                bookingId: booking.bookingId,
                onOpenChat: () => _openChat(booking),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GoogleMap(
                        onMapCreated: _onMapCreated,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: false,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.sizeOf(context).height * 0.18,
                        ),
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

                    if (booking.bookingId.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TripStatusCard(
                          status: booking.status,
                          role: RideParticipantRole.passenger,
                          eta: _eta,
                          distance: _remainingDistance,
                        ),
                      ),

                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                DriverInformationCard(
                                  driverName:
                                      booking.driverName ?? 'VolTrike driver',
                                  vehicleNumber:
                                      booking.vehicleNumber ?? 'Not available',
                                  plateNumber:
                                      booking.plateNumber ?? 'Not available',
                                  todaName: booking.todaName ?? 'Not available',
                                  photoUrl: booking.driverPhotoUrl,
                                  rating: booking.driverRating,
                                ),

                                const SizedBox(height: 16),

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
                      ),
                    ],
                    DraggableScrollableSheet(
                      initialChildSize: 0.48,
                      minChildSize: 0.16,
                      maxChildSize: 0.88,
                      snap: true,
                      snapSizes: const [0.16, 0.48, 0.88],
                      builder: (context, scrollController) => _trackingSheet(
                        booking: booking,
                        scrollController: scrollController,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
