import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/fare_service.dart';
import '../../../../core/services/places_service.dart';
import '../../../../core/services/polyline_service.dart';
import '../../../../core/services/route_restriction_service.dart';
import '../../../../core/services/routes_service.dart';
import '../../../../data/models/place_prediction.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/booking_session_provider.dart';
import '../../providers/fare_configuration_provider.dart';
import '../widgets/home_bottom_sheet.dart';
import '../widgets/map_view.dart';
import 'destination_search_screen.dart';

/// ===========================================================================
/// Passenger Home Screen
///
/// Booking Flow
///
/// Pickup
///      ↓
/// Destination
///      ↓
/// Route Calculation
///      ↓
/// Fare Calculation
///      ↓
/// Book Ride
/// ===========================================================================
class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  FareConfiguration get _fareConfiguration =>
      ref.read(fareConfigurationProvider).valueOrNull ?? devFareConfiguration;

  //==========================================================================
  // Select Pickup
  //==========================================================================

  Future<void> _selectPickup() async {
    final PlacePrediction? prediction = await Navigator.push<PlacePrediction>(
      context,
      MaterialPageRoute(
        builder: (_) => const DestinationSearchScreen(
          title: 'Choose Pickup',
          hintText: 'Search pickup location',
        ),
      ),
    );

    if (!mounted || prediction == null) {
      return;
    }

    final details = await PlacesService.getPlaceDetails(prediction.placeId);

    if (!mounted || details == null) {
      return;
    }

    ref
        .read(bookingSessionProvider.notifier)
        .updatePickup(
          pickup: LatLng(
            details['latitude'] as double,
            details['longitude'] as double,
          ),
          pickupName: details['name'] as String,
          pickupAddress: details['address'] as String,
        );
  }

  //==========================================================================
  // Select Destination
  //==========================================================================

  Future<void> _selectDestination() async {
    final booking = ref.read(bookingSessionProvider);
    if (booking.pickup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a pickup location first.')),
      );
      return;
    }

    final PlacePrediction? prediction = await Navigator.push<PlacePrediction>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationSearchScreen(
          title: 'Choose Destination',
          hintText: 'Search destination',
          searchOrigin: booking.pickup,
        ),
      ),
    );

    if (!mounted || prediction == null) {
      return;
    }

    final details = await PlacesService.getPlaceDetails(prediction.placeId);

    if (!mounted || details == null) {
      return;
    }

    await _calculateRoute(
      pickup: booking.pickup!,
      pickupName: booking.pickupName ?? 'Pickup',
      pickupAddress: booking.pickupAddress ?? booking.pickupName ?? 'Pickup',
      destination: LatLng(
        details['latitude'] as double,
        details['longitude'] as double,
      ),
      destinationName: details['name'] as String,
      destinationAddress: details['address'] as String,
    );
  }

  //==========================================================================
  // Calculate Route
  //==========================================================================

  Future<void> _calculateRoute({
    required LatLng pickup,
    required String pickupName,
    required String pickupAddress,
    required LatLng destination,
    required String destinationName,
    required String destinationAddress,
  }) async {
    ref
        .read(bookingProvider.notifier)
        .update(PassengerBookingState.estimatingFare);

    final result = await RoutesService.computeRoute(
      origin: pickup,
      destination: destination,
    );

    if (!mounted || result == null) {
      ref.read(bookingProvider.notifier).reset();

      if (mounted) {
        final restriction = RouteRestrictionService.instance.lastConflict;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restriction == null
                  ? 'Unable to calculate a route right now.'
                  : 'No safe route is available because of ${restriction.name}.',
            ),
          ),
        );
      }

      return;
    }

    final routePoints = PolylineService.decodePolyline(result.encodedPolyline);

    final booking = ref.read(bookingSessionProvider);

    final fare = FareService.calculateFare(
      config: _fareConfiguration,
      distanceMeters: result.distanceMeters,
      passengerCount: booking.additionalPassengers + 1,
      baggageCount: booking.baggageCount,
      isOutsideToda: booking.isOutsideToda,
    );

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          booking.copyWith(
            pickup: pickup,
            pickupName: pickupName,
            pickupAddress: pickupAddress,
            destination: destination,
            destinationName: destinationName,
            destinationAddress: destinationAddress,
            routePoints: routePoints,
            distanceMeters: result.distanceMeters,
            duration: '${result.durationMinutes} mins',

            baseFare: fare.baseFare,
            distanceFare: fare.distanceFare,
            additionalPassengerFee: fare.additionalPassengerFee,
            baggageFee: fare.baggageFee,
            boundarySurcharge: fare.boundarySurcharge,
            estimatedFare: fare.totalFare,

            hasRoute: true,
          ),
        );

    ref.read(bookingProvider.notifier).reset();
  }

  //==========================================================================
  // Recalculate Fare
  //==========================================================================

  void _recalculateFare() {
    final session = ref.read(bookingSessionProvider);

    if (!session.hasRoute) {
      return;
    }

    final fare = FareService.calculateFare(
      config: _fareConfiguration,
      distanceMeters: session.distanceMeters,
      passengerCount: session.additionalPassengers + 1,
      baggageCount: session.baggageCount,
      isOutsideToda: session.isOutsideToda,
    );

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            baseFare: fare.baseFare,
            distanceFare: fare.distanceFare,
            additionalPassengerFee: fare.additionalPassengerFee,
            baggageFee: fare.baggageFee,
            boundarySurcharge: fare.boundarySurcharge,
            estimatedFare: fare.totalFare,
          ),
        );
  }

  //==========================================================================
  // Additional Passengers
  //==========================================================================

  void _increasePassengers() {
    final session = ref.read(bookingSessionProvider);

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            additionalPassengers: session.additionalPassengers + 1,
          ),
        );

    _recalculateFare();
  }

  void _decreasePassengers() {
    final session = ref.read(bookingSessionProvider);

    if (session.additionalPassengers == 0) {
      return;
    }

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            additionalPassengers: session.additionalPassengers - 1,
          ),
        );

    _recalculateFare();
  }

  //==========================================================================
  // Baggage
  //==========================================================================

  void _increaseBaggage() {
    final session = ref.read(bookingSessionProvider);

    ref
        .read(bookingSessionProvider.notifier)
        .update(session.copyWith(baggageCount: session.baggageCount + 1));

    _recalculateFare();
  }

  void _decreaseBaggage() {
    final session = ref.read(bookingSessionProvider);

    if (session.baggageCount == 0) {
      return;
    }

    ref
        .read(bookingSessionProvider.notifier)
        .update(session.copyWith(baggageCount: session.baggageCount - 1));

    _recalculateFare();
  }

  //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(bookingSessionProvider);

    final bookingState = ref.watch(bookingProvider);

    return Scaffold(
      appBar: const AppAppBar(title: 'VolTrike', showNotifications: true),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapView(
              pickup: session.pickup,
              destination: session.destination,
              routePoints: session.routePoints,
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.18,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return HomeBottomSheet(
                scrollController: scrollController,

                pickup: session.pickupName ?? 'Select pickup',

                destination: session.destinationName ?? 'Where are you going?',

                onPickupTap:
                    bookingState == PassengerBookingState.searchingDriver
                    ? null
                    : _selectPickup,

                onDestinationTap:
                    bookingState == PassengerBookingState.searchingDriver
                    ? null
                    : _selectDestination,

                estimatedFare: '₱${session.estimatedFare.toStringAsFixed(2)}',

                distance: session.distanceMeters == 0
                    ? '--'
                    : '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',

                eta: session.duration.isEmpty ? '--' : session.duration,

                additionalPassengers: session.additionalPassengers,

                baggageCount: session.baggageCount,

                baggageFee: '₱${session.baggageFee.toStringAsFixed(2)}',

                boundarySurcharge:
                    '₱${session.boundarySurcharge.toStringAsFixed(2)}',

                hasRoute: session.hasRoute,

                onIncreasePassengers: _increasePassengers,

                onDecreasePassengers: _decreasePassengers,

                onIncreaseBaggage: _increaseBaggage,

                onDecreaseBaggage: _decreaseBaggage,

                onBookRide: session.hasRoute ? _bookRide : null,
              );
            },
          ),
        ],
      ),
    );
  }

  //==========================================================================
  // Book Ride
  //==========================================================================

  Future<void> _bookRide() async {
    final session = ref.read(bookingSessionProvider);

    if (!session.hasRoute ||
        session.pickup == null ||
        session.destination == null) {
      return;
    }

    try {
      final bookingId = await ref
          .read(bookingControllerProvider.notifier)
          .createBooking(
            session: session,
            pickupLatitude: session.pickup!.latitude,
            pickupLongitude: session.pickup!.longitude,
            pickupAddress:
                session.pickupAddress ?? session.pickupName ?? 'Pickup',
            destinationAddress:
                session.destinationAddress ??
                session.destinationName ??
                'Destination',
          );

      if (!mounted) {
        return;
      }

      ref
          .read(bookingProvider.notifier)
          .update(PassengerBookingState.searchingDriver);

      context.go(AppRoutes.searchingDriver, extra: bookingId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    }
  }
}
