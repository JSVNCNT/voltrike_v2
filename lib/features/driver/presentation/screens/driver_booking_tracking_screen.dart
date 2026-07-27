import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:voltrike_v2/features/driver/providers/driver_location_provider.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../../data/repositories/safety_repository.dart';
import '../../../../app/routes.dart';

import '../../providers/driver_current_booking_provider.dart';
import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_navigation_provider.dart';
import '../../controllers/driver_navigation_controller.dart';
import '../../services/external_navigation_service.dart';

import '../widgets/passenger_information_card.dart';

import '../../../ride/tracking/widgets/trip_information_card.dart';
import '../../../ride/tracking/widgets/trip_status_card.dart';
import '../../../ride/tracking/models/ride_participant_role.dart';
import '../../../ride/tracking/models/ride_action.dart';
import '../../../ride/tracking/services/ride_action_service.dart';
import '../../../ride/tracking/services/ride_stage_presentation_service.dart';
import '../../../ride/tracking/widgets/ride_actions_card.dart';
import '../../../ride/tracking/widgets/ride_cancel_dialog.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../../ride/tracking/widgets/ride_primary_button.dart';
import '../../../ride/chat/ride_chat_alert_listener.dart';

class DriverBookingTrackingScreen extends ConsumerStatefulWidget {
  const DriverBookingTrackingScreen({super.key, this.bookingId});

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
  ProviderSubscription<Booking?>? _bookingSubscription;
  String? _finishingBookingId;

  @override
  void initState() {
    super.initState();
    _bookingSubscription = ref.listenManual<Booking?>(
      driverCurrentBookingProvider,
      (previous, next) {
        if (previous != null && next == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final completedBookingId = _finishingBookingId;
              if (completedBookingId != null) {
                _finishingBookingId = null;
                context.go(AppRoutes.driverReceipt, extra: completedBookingId);
              } else {
                context.go(AppRoutes.driverHome);
              }
            }
          });
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreBooking();
    });
  }

  Future<void> _restoreBooking() async {
    final booking = await ref
        .read(driverBookingControllerProvider.notifier)
        .restoreCurrentBooking();
    if (mounted && booking == null) {
      context.go(AppRoutes.driverHome);
    }
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void dispose() {
    _bookingSubscription?.close();
    _mapController?.dispose();
    super.dispose();
  }

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

  Future<void> _openExternalNavigation(Booking booking) async {
    final app = await showModalBottomSheet<ExternalNavigationApp>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Google Maps'),
              onTap: () =>
                  Navigator.pop(context, ExternalNavigationApp.googleMaps),
            ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: const Text('Waze'),
              onTap: () => Navigator.pop(context, ExternalNavigationApp.waze),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Choose navigation app'),
              onTap: () =>
                  Navigator.pop(context, ExternalNavigationApp.chooser),
            ),
          ],
        ),
      ),
    );
    if (app == null) return;
    try {
      await const ExternalNavigationService().open(
        app: app,
        destination: _routeDestination(booking),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation app unavailable. Try another option.'),
        ),
      );
    }
  }

  Widget _driverNavigation([Booking? activeBooking]) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        const routes = [
          AppRoutes.driverHome,
          AppRoutes.driverDashboard,
          AppRoutes.driverTripHistory,
          AppRoutes.driverProfile,
        ];
        if (index == 0 && activeBooking != null) {
          context.go(
            AppRoutes.driverBookingTracking,
            extra: activeBooking.bookingId,
          );
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
    required LatLng driverLocation,
  }) async {
    await ref
        .read(driverNavigationControllerProvider.notifier)
        .checkCurrentPosition(driverLocation);
    await _moveCamera(driverLocation);

    final destination = _routeDestination(booking);
    await ref
        .read(driverNavigationControllerProvider.notifier)
        .loadRoute(origin: driverLocation, destination: destination);
  }

  Future<void> _advanceRide(Booking booking) async {
    if (ref.read(driverBookingControllerProvider).isLoading) return;
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
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Drop off passenger?'),
              content: const Text(
                'Confirm only after reaching the destination. Cash will be '
                'confirmed in the next step.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not yet'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm drop off'),
                ),
              ],
            ),
          );
          if (confirmed == true) await controller.confirmDropOff(booking);
          break;
        case BookingStatus.paymentConfirmation:
          final received = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cash received?'),
              content: Text(
                'Confirm receipt of ₱${booking.amountDue.toStringAsFixed(2)} '
                'to complete the trip.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not yet'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cash received'),
                ),
              ],
            ),
          );
          if (received != true) return;
          _finishingBookingId = booking.bookingId;
          await controller.completeTrip(booking);
          break;
        case BookingStatus.pending:
        case BookingStatus.completed:
        case BookingStatus.cancelled:
          return;
      }
    } catch (error) {
      _finishingBookingId = null;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update trip: $error')));
    }
  }

  Future<void> _markNoShow(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Passenger did not arrive?'),
        content: const Text(
          'Use this only after reaching the pickup and waiting for the '
          'passenger. The booking will be cancelled as a passenger no-show.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark no-show'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(driverBookingControllerProvider.notifier)
          .markPassengerNoShow(booking);
      if (mounted) context.go(AppRoutes.driverHome);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not mark no-show: $error')));
    }
  }

  Future<void> _cancelRide(Booking booking) async {
    final result = await showDialog<RideCancellationResult>(
      context: context,
      builder: (_) => const RideCancelDialog(isDriver: true),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(driverBookingControllerProvider.notifier)
          .cancelTrip(
            booking,
            reasonCode: result.reason.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]+'),
              '_',
            ),
            reasonDetail: result.comment,
          );
      if (!mounted) return;
      context.go(AppRoutes.driverHome);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel trip: $error')));
    }
  }

  Future<void> _reportPassenger(Booking booking) async {
    await showRideReportDialog(
      context: context,
      booking: booking,
      reporterIsDriver: true,
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

  Widget _rideActions(Booking booking) {
    final stage = RideStagePresentationService.resolve(
      role: RideParticipantRole.driver,
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
      builder: (context, snapshot) => RideActionsCard(
        onCall: stage.allowContact
            ? () => context.push(
                AppRoutes.bookingVoiceCall,
                extra: booking.bookingId,
              )
            : null,
        onMessage: stage.allowContact
            ? () => context.push(
                AppRoutes.bookingChat,
                extra: {
                  'bookingId': booking.bookingId,
                  'members': [booking.passengerId, booking.driverId!],
                },
              )
            : null,
        onCancel: stage.allowCancel ? () => _cancelRide(booking) : null,
        onReport: stage.allowReport ? () => _reportPassenger(booking) : null,
        onSos: stage.allowSos ? () => _triggerSos(booking) : null,
        onNoShow: stage.allowNoShow ? () => _markNoShow(booking) : null,
        messageBadge: snapshot.data ?? 0,
      ),
    );
  }

  Widget _trackingSheet({
    required Booking booking,
    required LatLng? driverLocation,
    required DriverNavigationState navigation,
    required RidePrimaryAction primaryAction,
    required ScrollController scrollController,
  }) {
    return Material(
      elevation: 10,
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              children: [
                if (navigation.restrictionWarning?.isNotEmpty == true) ...[
                  Material(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(navigation.restrictionWarning!)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TripStatusCard(
                  status: booking.status,
                  role: RideParticipantRole.driver,
                  eta: navigation.eta,
                  distance: navigation.distance,
                ),
                if (navigation.instruction?.isNotEmpty == true)
                  Card(
                    color: Colors.teal.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.navigation, color: Colors.teal),
                      title: Text(navigation.instruction!),
                      subtitle: navigation.nextInstruction == null
                          ? null
                          : Text('Next: ${navigation.nextInstruction}'),
                    ),
                  ),
                PassengerInformationCard(
                  passengerName: booking.passengerName ?? 'Passenger',
                  photoUrl: booking.passengerPhotoUrl,
                ),
                _rideActions(booking),
                if (booking.status == BookingStatus.driverAssigned ||
                    booking.status == BookingStatus.driverArriving ||
                    booking.status == BookingStatus.passengerOnBoard ||
                    booking.status == BookingStatus.paymentConfirmation)
                  OutlinedButton.icon(
                    onPressed: () => _openExternalNavigation(booking),
                    icon: const Icon(Icons.navigation_outlined),
                    label: Text(
                      _tripStarted(booking)
                          ? 'Navigate to Destination'
                          : 'Navigate to Pickup',
                    ),
                  ),
                const SizedBox(height: 10),
                TripInformationCard(
                  pickup: booking.pickupAddress,
                  destination: booking.destinationAddress,
                  distance:
                      '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                  duration: navigation.duration ?? '--',
                  fare: '₱${booking.estimatedFare.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),
          if (primaryAction != RidePrimaryAction.none)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: RidePrimaryButton(
                action: primaryAction,
                onPressed: () => _advanceRide(booking),
              ),
            ),
        ],
      ),
    );
  }

  //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(driverCurrentBookingProvider);

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Current Trip')),
        body: const Center(child: Text('No active booking.')),
        bottomNavigationBar: _driverNavigation(),
      );
    }

    //==========================================================================
    // Providers
    //==========================================================================

    final navigation = ref.watch(driverNavigationControllerProvider);

    final driverLocation = ref.watch(driverLocationProvider);

    final primaryAction =
        booking.status == BookingStatus.driverAssigned ||
            booking.status == BookingStatus.driverArriving ||
            booking.status == BookingStatus.passengerOnBoard ||
            booking.status == BookingStatus.paymentConfirmation
        ? RideActionService.driverPrimaryAction(booking.status)
        : RidePrimaryAction.none;

    //==========================================================================
    // Follow Driver
    //==========================================================================

    if (driverLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _followDriver(booking: booking, driverLocation: driverLocation);
      });
    }

    //==========================================================================
    // UI
    //==========================================================================

    return Scaffold(
      appBar: AppBar(title: const Text('Current Trip')),
      bottomNavigationBar: _driverNavigation(booking),
      body: RideChatAlertListener(
        bookingId: booking.bookingId,
        onOpenChat: () => context.push(
          AppRoutes.bookingChat,
          extra: {
            'bookingId': booking.bookingId,
            'members': [booking.passengerId, booking.driverId!],
          },
        ),
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
                markers: {
                  if (driverLocation != null)
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: driverLocation,
                      infoWindow: const InfoWindow(title: 'Driver'),
                    ),
                  Marker(
                    markerId: const MarkerId('pickup'),
                    position: booking.pickup,
                    infoWindow: const InfoWindow(title: 'Pickup'),
                  ),
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: booking.destination,
                    infoWindow: const InfoWindow(title: 'Destination'),
                  ),
                },
                polylines: {
                  if (navigation.routePoints.isNotEmpty)
                    Polyline(
                      polylineId: const PolylineId('route'),
                      points: navigation.routePoints,
                      width: 5,
                    ),
                },
              ),
            ),

            if (booking.bookingId.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (navigation.restrictionWarning?.isNotEmpty == true) ...[
                      Material(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(navigation.restrictionWarning!),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TripStatusCard(
                      status: booking.status,
                      role: RideParticipantRole.driver,
                      eta: navigation.eta,
                      distance: navigation.distance,
                    ),
                    if (navigation.instruction?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Card(
                        color: Colors.teal.shade50,
                        child: ListTile(
                          leading: const Icon(
                            Icons.navigation,
                            color: Colors.teal,
                          ),
                          title: Text(navigation.instruction!),
                          subtitle: navigation.nextInstruction == null
                              ? null
                              : Text('Next: ${navigation.nextInstruction}'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      PassengerInformationCard(
                        passengerName: booking.passengerName ?? 'Passenger',
                        photoUrl: booking.passengerPhotoUrl,
                      ),

                      const SizedBox(height: 16),

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

                      const SizedBox(height: 16),

                      TripInformationCard(
                        pickup: booking.pickupAddress,
                        destination: booking.destinationAddress,
                        distance:
                            '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                        duration: navigation.duration ?? '--',
                        fare: '₱${booking.estimatedFare.toStringAsFixed(2)}',
                      ),
                    ],
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
                driverLocation: driverLocation,
                navigation: navigation,
                primaryAction: primaryAction,
                scrollController: scrollController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
