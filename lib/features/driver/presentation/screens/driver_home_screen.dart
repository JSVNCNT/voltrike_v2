import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/app/routes.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../data/models/booking.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';

import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_booking_listener_provider.dart';
import '../../providers/driver_current_booking_provider.dart';
import '../../providers/driver_incoming_booking_provider.dart';
import '../../providers/driver_location_controller_provider.dart';
import '../../providers/driver_location_provider.dart';
import '../../providers/driver_offer_cooldown_provider.dart';
import '../../providers/driver_status_provider.dart';

import '../widgets/booking_request_card.dart';
import '../widgets/driver_bottom_sheet.dart';
import '../widgets/driver_map_view.dart';
import '../../../ride/tracking/widgets/ride_cancel_dialog.dart';

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
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  bool _isAcceptingBooking = false;
  bool _isChangingAvailability = false;

  Future<void> _cancelTrip() async {
    final booking = ref.read(driverCurrentBookingProvider);
    if (booking == null) return;

    final result = await showDialog<RideCancellationResult>(
      context: context,
      builder: (_) => const RideCancelDialog(isDriver: true),
    );
    if (result == null || !mounted) return;

    try {
      await ref
          .read(driverBookingControllerProvider.notifier)
          .cancelTrip(booking);
      if (!mounted) return;
      setState(() => _routePoints.clear());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trip cancelled.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel trip: $error')));
    }
  }

  //==========================================================================
  // Navigation
  //==========================================================================

  final NavigationService _navigation = NavigationService.instance;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDriver();
    });
  }

  Future<void> _initializeDriver() async {
    final user = ref.read(driverAuthRepositoryProvider).currentUser;
    if (user == null) return;

    final driver = await ref.read(driverRepositoryProvider).getDriver(user.uid);
    if (!mounted) return;
    if (driver == null) return;
    // A completed receipt belongs in trip history, never in the active-driver
    // recovery path. In particular, a delayed acknowledgement must not trap a
    // driver in an old receipt after they selected "Back to Home", restarted,
    // or signed in on a new device.
    if (!driver.isOnline) {
      ref.read(driverStatusProvider.notifier).goOffline();
      return;
    }

    final hasActiveBooking = driver.currentBookingId?.isNotEmpty == true;
    final status = ref.read(driverStatusProvider.notifier);
    if (hasActiveBooking || !driver.isAvailable) {
      status.goBusy();
    } else {
      status.goOnline();
    }

    try {
      await ref.read(driverLocationControllerProvider.notifier).startTracking();
      if (!hasActiveBooking && driver.isAvailable) {
        ref.read(driverBookingListenerProvider).startListening();
      }
    } catch (_) {
      // Do not leave the idle switch claiming that the driver is available
      // when a fresh session or location publication could not be started.
      if (!hasActiveBooking) {
        status.goOffline();
      }
    }
  }

  //==========================================================================
  // Online / Offline
  //==========================================================================

  Future<void> _toggleOnline(bool online) async {
    if (_isChangingAvailability) return;
    setState(() => _isChangingAvailability = true);
    final statusNotifier = ref.read(driverStatusProvider.notifier);

    final bookingController = ref.read(
      driverBookingControllerProvider.notifier,
    );

    final bookingListener = ref.read(driverBookingListenerProvider);

    try {
      if (online) {
        // goOnline creates the server session and starts location tracking.
        // Only show "online" after that complete operation succeeds.
        await bookingController.goOnline();
        statusNotifier.goOnline();
        bookingListener.startListening();
      } else {
        // goOffline stops the same tracking session and publishes offline.
        await bookingController.goOffline();
        await bookingListener.stopListening();
        statusNotifier.goOffline();
        if (mounted) setState(() => _routePoints.clear());
      }
    } catch (error) {
      if (online) {
        await bookingListener.stopListening();
        statusNotifier.goOffline();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DomainErrorMapper.message(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingAvailability = false);
    }
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
  // Driver Actions
  //==========================================================================

  Future<void> _acceptBooking() async {
    if (_isAcceptingBooking) {
      return;
    }

    final booking = ref.read(driverIncomingBookingProvider);

    if (booking == null) {
      return;
    }

    setState(() => _isAcceptingBooking = true);

    try {
      await ref
          .read(driverBookingControllerProvider.notifier)
          .acceptBooking(booking);

      // Remove the pending booking only after the backend transaction commits.
      ref.read(driverIncomingBookingProvider.notifier).clearBooking();
      if (mounted) {
        context.go(
          AppRoutes.withBookingId(
            AppRoutes.driverBookingTracking,
            booking.bookingId,
          ),
          extra: booking.bookingId,
        );
      }
    } catch (error) {
      if (!mounted) return;

      final message = error.toString();
      final isExpired = message.toLowerCase().contains('offer has expired');
      if (isExpired) {
        ref.read(driverIncomingBookingProvider.notifier).clearBooking();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isExpired
                ? 'This booking request expired. Waiting for a new request.'
                : 'Could not accept booking: $message',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAcceptingBooking = false);
      }
    }
  }

  Future<void> _declineBooking() async {
    final booking = ref.read(driverIncomingBookingProvider);

    if (booking == null) {
      return;
    }

    try {
      final declined = await ref
          .read(driverBookingControllerProvider.notifier)
          .declineBooking(booking);
      if (!mounted) return;

      if (!declined) {
        ref.read(driverIncomingBookingProvider.notifier).clearBooking();
        setState(() => _routePoints.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This booking request is no longer available.'),
          ),
        );
        return;
      }

      await ref.read(driverBookingListenerProvider).stopListening();
      if (!mounted) return;

      ref.read(driverOfferCooldownProvider.notifier).start();
      ref.read(driverIncomingBookingProvider.notifier).clearBooking();
      setState(() => _routePoints.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking declined. New offers resume in 30 seconds.'),
        ),
      );

      Future<void>.delayed(const Duration(seconds: 30), () {
        if (!mounted ||
            ref.read(driverStatusProvider) == DriverStatus.offline) {
          return;
        }
        ref.read(driverBookingListenerProvider).startListening();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not decline booking: ${DomainErrorMapper.message(error)}',
          ),
        ),
      );
    }
  }

  //==========================================================================
  // Navigation
  //==========================================================================

  Future<void> _navigateToPickup() async {
    final booking = ref.read(driverCurrentBookingProvider);

    final driverLocation = ref.read(driverLocationProvider);

    if (booking == null || driverLocation == null) {
      return;
    }

    final route = await _navigation.computeTrafficRoute(
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
      _routePoints = _navigation.decodePolyline(
        _navigation.encodedPolyline(route),
      );
    });
  }

  Future<void> _navigateToDestination() async {
    final booking = ref.read(driverCurrentBookingProvider);

    final driverLocation = ref.read(driverLocationProvider);

    if (booking == null || driverLocation == null) {
      return;
    }

    final route = await _navigation.computeTrafficRoute(
      origin: driverLocation,
      destination: booking.activeDestinationStop.location,
    );

    if (route == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _routePoints = _navigation.decodePolyline(
        _navigation.encodedPolyline(route),
      );
    });
  }

  //==========================================================================
  // Trip Lifecycle
  //==========================================================================

  Future<void> _arrived() async {
    final booking = ref.read(driverCurrentBookingProvider);

    if (booking == null) {
      return;
    }

    await ref.read(driverBookingControllerProvider.notifier).arrived(booking);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Passenger pickup reached.')));
  }

  Future<void> _startTrip() async {
    final booking = ref.read(driverCurrentBookingProvider);

    if (booking == null) {
      return;
    }

    await ref.read(driverBookingControllerProvider.notifier).startTrip(booking);

    await _navigateToDestination();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trip started.')));
  }

  Future<void> _completeTrip() async {
    if (ref.read(driverBookingControllerProvider).isLoading) return;
    final booking = ref.read(driverCurrentBookingProvider);

    if (booking == null) {
      return;
    }

    final controller = ref.read(driverBookingControllerProvider.notifier);
    if (booking.status == BookingStatus.passengerOnBoard) {
      await controller.confirmDropOff(booking);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              booking.hasMultipleDropoffs &&
                      !booking.activeDestinationStop.isFinal
                  ? 'First drop-off confirmed. Continue to the final stop.'
                  : 'Drop-off confirmed. Confirm cash next.',
            ),
          ),
        );
      }
      return;
    }
    if (booking.status != BookingStatus.paymentConfirmation) return;
    await controller.completeTrip(booking);

    if (!mounted) {
      return;
    }

    context.go(AppRoutes.driverHome);

    ref.read(driverCurrentBookingProvider.notifier).clearBooking();

    if (mounted) {
      setState(() {
        _routePoints.clear();
      });
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Trip completed.')));
  }

  //==========================================================================
  // UI
  //==========================================================================

  @override
  Widget build(BuildContext context) {
    final incomingBooking = ref.watch(driverIncomingBookingProvider);

    final currentBooking = ref.watch(driverCurrentBookingProvider);

    final driverLocation = ref.watch(driverLocationProvider);

    final driverStatus = ref.watch(driverStatusProvider);

    final offerCooldown = ref.watch(driverOfferCooldownProvider);

    final hasIncomingBooking =
        incomingBooking != null && !offerCooldown.isActive;
    final canRespondToOffer = hasIncomingBooking && !_isAcceptingBooking;

    // A stale driver profile can briefly point at a legacy, pending, or
    // terminal booking. It is not an active trip and must not make the idle
    // sheet look like a passenger request.
    final activeBooking = switch (currentBooking?.status) {
      BookingStatus.driverAssigned ||
      BookingStatus.driverArriving ||
      BookingStatus.passengerOnBoard ||
      BookingStatus.paymentConfirmation
          when _hasUsableTripAddresses(currentBooking) =>
        currentBooking,
      _ => null,
    };
    final hasCurrentBooking = activeBooking != null;

    // Booking shown in the bottom sheet.
    // Before acceptance -> incoming booking.
    // After acceptance -> active booking.
    final displayBooking = activeBooking ?? incomingBooking;

    return Scaffold(
      appBar: const AppAppBar(title: 'Driver'),
      body: Stack(
        children: [
          //------------------------------------------------------------------
          // Map
          //------------------------------------------------------------------
          Positioned.fill(
            child: DriverMapView(
              driverLocation: driverLocation,
              pickupLocation: displayBooking?.pickup,
              destinationLocation:
                  displayBooking?.activeDestinationStop.location,
              routePoints: _routePoints,
            ),
          ),

          //------------------------------------------------------------------
          // Incoming Booking Card
          //------------------------------------------------------------------
          if (hasIncomingBooking)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: BookingRequestCard(
                  passengerName: incomingBooking.passengerName ?? 'Passenger',
                  passengerPhotoUrl: incomingBooking.passengerPhotoUrl,
                  pickupName: incomingBooking.pickupName,
                  pickupAddress: incomingBooking.pickupAddress,
                  destinationName: incomingBooking.destinationName,
                  destinationAddress: incomingBooking.destinationAddress,
                  estimatedFare:
                      '₱${incomingBooking.estimatedFare.toStringAsFixed(2)}',
                  distance:
                      '${(incomingBooking.distanceMeters / 1000).toStringAsFixed(1)} km',
                  routeAdvisory: incomingBooking.routePolicy.driverMessage,
                  routeStops: incomingBooking.routeStops,
                  passengerNote: incomingBooking.passengerNote,
                  onAccept: canRespondToOffer ? _acceptBooking : null,
                  onDecline: canRespondToOffer ? _declineBooking : null,
                ),
              ),
            ),

          //------------------------------------------------------------------
          // Bottom Sheet
          //------------------------------------------------------------------
          if (!hasIncomingBooking)
            Align(
              alignment: Alignment.bottomCenter,
              child: DriverBottomSheet(
                isOnline: driverStatus != DriverStatus.offline,

                offerCooldownSeconds: offerCooldown.secondsRemaining,

                // Keep the idle sheet truly empty. A fallback name here made
                // the sheet look as though an offer existed before one had
                // been received, including blank pickup and destination rows.
                passengerName: hasIncomingBooking
                    ? (incomingBooking.passengerName ?? 'Passenger')
                    : activeBooking?.passengerName,

                pickupAddress: hasIncomingBooking
                    ? incomingBooking.pickupAddress
                    : activeBooking?.pickupAddress,

                destinationAddress: hasIncomingBooking
                    ? incomingBooking.destinationAddress
                    : activeBooking?.destinationAddress,

                estimatedFare: displayBooking == null || offerCooldown.isActive
                    ? null
                    : '₱${displayBooking.estimatedFare.toStringAsFixed(2)}',

                distance: displayBooking == null || offerCooldown.isActive
                    ? null
                    : '${displayBooking.distanceMeters} m',

                bookingStatus: activeBooking?.status,

                onOnlineChanged: _isChangingAvailability ? null : _toggleOnline,

                onAcceptBooking: canRespondToOffer ? _acceptBooking : null,

                onDeclineBooking: canRespondToOffer ? _declineBooking : null,

                onNavigate: hasCurrentBooking ? _navigateToPickup : null,

                onArrived: hasCurrentBooking ? _arrived : null,

                onStartTrip: hasCurrentBooking ? _startTrip : null,

                onCompleteTrip: hasCurrentBooking ? _completeTrip : null,

                onCancelTrip: hasCurrentBooking ? _cancelTrip : null,
              ),
            ),
        ],
      ),
    );
  }

  bool _hasUsableTripAddresses(Booking? booking) {
    if (booking == null) return false;
    return _isUsableAddress(booking.pickupAddress) &&
        _isUsableAddress(booking.destinationAddress);
  }

  bool _isUsableAddress(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty &&
        normalized != '--' &&
        normalized != 'pickup location' &&
        normalized != 'destination';
  }
}
