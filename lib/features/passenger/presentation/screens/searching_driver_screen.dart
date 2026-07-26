import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../data/models/booking.dart';

import '../../controllers/passenger_booking_flow_controller.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_listener_provider.dart';

import '../../../ride/routing/booking_route_coordinator.dart';
import '../../../ride/routing/booking_route_resolver.dart';

/// ===========================================================================
/// Searching Driver Screen
///
/// Displays realtime booking updates while waiting for a driver.
///
/// Once a driver is assigned, navigation moves to
/// BookingTrackingScreen, which handles both:
///
/// • Driver → Pickup
/// • Driver → Destination
///
/// RatingScreen is shown after the booking is completed.
/// ===========================================================================
class SearchingDriverScreen extends ConsumerStatefulWidget {
  const SearchingDriverScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<SearchingDriverScreen> createState() =>
      _SearchingDriverScreenState();
}

class _SearchingDriverScreenState extends ConsumerState<SearchingDriverScreen> {
  BookingStatus? _lastStatus;
  bool _cancelling = false;
  String? _loadedRouteBookingId;
  List<LatLng> _routePoints = const [];

  ProviderSubscription<AsyncValue<Booking?>>? _bookingSubscription;

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void initState() {
    super.initState();

    _bookingSubscription = ref.listenManual<AsyncValue<Booking?>>(
      bookingListenerProvider(widget.bookingId),
      (previous, next) {
        next.whenData((booking) {
          if (booking == null) {
            ref.read(passengerBookingFlowProvider.notifier).clear();
            return;
          }

          ref
              .read(passengerBookingFlowProvider.notifier)
              .updateStatus(booking.status);

          _loadRequestedRoute(booking);
          _handleStatusChange(booking);
        });
      },
    );
  }

  Future<void> _loadRequestedRoute(Booking booking) async {
    if (_loadedRouteBookingId == booking.bookingId) return;
    _loadedRouteBookingId = booking.bookingId;
    try {
      final route = await NavigationService.instance.computeRouteInfo(
        origin: booking.pickup,
        destination: booking.destination,
      );
      final points = route == null || route.encodedPolyline.isEmpty
          ? <LatLng>[booking.pickup, booking.destination]
          : NavigationService.instance.decodePolyline(route.encodedPolyline);
      if (mounted) setState(() => _routePoints = points);
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePoints = [booking.pickup, booking.destination];
        });
      }
    }
  }

  @override
  void dispose() {
    _bookingSubscription?.close();
    super.dispose();
  }

  //==========================================================================
  // Navigation
  //==========================================================================

  void _handleStatusChange(Booking booking) {
    if (_lastStatus == booking.status) {
      return;
    }

    _lastStatus = booking.status;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (booking.status == BookingStatus.pending) return;
      BookingRouteCoordinator.open(
        context,
        role: BookingParticipantRole.passenger,
        booking: booking,
      );
    });
  }

  //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingListenerProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Searching Driver'),
        automaticallyImplyLeading: false,
      ),
      body: booking.when(
        loading: () {
          return const Center(child: CircularProgressIndicator());
        },
        error: (error, _) {
          return Center(child: Text(DomainErrorMapper.message(error)));
        },
        data: (Booking? bookingData) {
          if (bookingData == null) {
            return const Center(child: Text('Booking not found.'));
          }

          final status = bookingData.status;

          late final String title;
          late final String message;
          late final IconData icon;
          late final Color color;

          switch (status) {
            //--------------------------------------------------------------
            // Pending
            //--------------------------------------------------------------

            case BookingStatus.pending:
              title = 'Searching for nearby drivers';
              message = 'Please wait while we find an available driver.';
              icon = Icons.search;
              color = Colors.orange;
              break;

            //--------------------------------------------------------------
            // Driver Assigned
            //--------------------------------------------------------------

            case BookingStatus.driverAssigned:
              title = 'Driver Assigned';
              message = 'A driver has accepted your booking.';
              icon = Icons.person_pin_circle;
              color = Colors.blue;
              break;

            //--------------------------------------------------------------
            // Driver Arriving
            //--------------------------------------------------------------

            case BookingStatus.driverArriving:
              title = 'Driver Arriving';
              message = 'Your driver is on the way.';
              icon = Icons.directions_car;
              color = Colors.green;
              break;

            //--------------------------------------------------------------
            // Trip Started
            //--------------------------------------------------------------

            case BookingStatus.passengerOnBoard:
              title = 'Trip In Progress';
              message = 'Opening trip tracker...';
              icon = Icons.route;
              color = Colors.blueAccent;
              break;

            case BookingStatus.paymentConfirmation:
              title = 'Payment Confirmation';
              message = 'Opening trip tracker...';
              icon = Icons.payments;
              color = Colors.blueAccent;
              break;

            //--------------------------------------------------------------
            // Completed
            //--------------------------------------------------------------

            case BookingStatus.completed:
              title = 'Trip Completed';
              message = 'Preparing your trip summary...';
              icon = Icons.check_circle;
              color = Colors.green;
              break;

            //--------------------------------------------------------------
            // Cancelled
            //--------------------------------------------------------------

            case BookingStatus.cancelled:
              title = switch (bookingData.cancellationCode) {
                'passenger_no_show' => 'Passenger No-show',
                'cancelled_by_passenger' => 'Cancelled by Passenger',
                'cancelled_by_driver' => 'Cancelled by Driver',
                _ => 'Booking Cancelled',
              };
              message = 'This booking has been cancelled.';
              icon = Icons.cancel;
              color = Colors.red;
              break;
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: bookingData.pickup,
                  zoom: 14,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('pickup'),
                    position: bookingData.pickup,
                    infoWindow: const InfoWindow(title: 'Pickup'),
                  ),
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: bookingData.destination,
                    infoWindow: const InfoWindow(title: 'Destination'),
                  ),
                },
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('requested_route'),
                    points: _routePoints.isEmpty
                        ? [bookingData.pickup, bookingData.destination]
                        : _routePoints,
                    color: Theme.of(context).colorScheme.primary,
                    width: 5,
                  ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
              ),
              SafeArea(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                  if (status == BookingStatus.pending)
                    const CircularProgressIndicator()
                  else
                    Icon(icon, size: 80, color: color),

                  const SizedBox(height: 32),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                  ),

                  const SizedBox(height: 24),

                  Chip(
                    avatar: Icon(icon, size: 18, color: Colors.white),
                    backgroundColor: color,
                    label: Text(
                      status.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (status == BookingStatus.pending)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelling ? null : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _cancelling = true);

                          try {
                            await ref
                                .read(bookingControllerProvider.notifier)
                                .cancelBooking(widget.bookingId);

                            if (!context.mounted) {
                              return;
                            }

                            context.go(AppRoutes.passengerHome);
                          } catch (e) {
                            if (!mounted) {
                              return;
                            }

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to cancel booking: $e'),
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _cancelling = false);
                          }
                        },
                        icon: const Icon(Icons.close),
                        label: Text(
                          _cancelling ? 'Cancelling...' : 'Cancel Booking',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
              ),
            ],
          );
        },
      ),
    );
  }
}
