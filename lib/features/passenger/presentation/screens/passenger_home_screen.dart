import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/fare_service.dart';
import '../../../../core/services/places_service.dart';
import '../../../../core/services/polyline_service.dart';
import '../../../../core/services/route_restriction_service.dart';
import '../../../../core/services/routes_service.dart';
import '../../../../core/services/toda_coverage_service.dart';
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
  int _routeCalculationGeneration = 0;

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
    final calculationGeneration = ++_routeCalculationGeneration;
    ref
        .read(bookingProvider.notifier)
        .update(PassengerBookingState.estimatingFare);

    final sessionNotifier = ref.read(bookingSessionProvider.notifier);
    final previousSession = ref.read(bookingSessionProvider);
    sessionNotifier.update(
      previousSession.copyWith(
        pickup: pickup,
        pickupName: pickupName,
        pickupAddress: pickupAddress,
        destination: destination,
        destinationName: destinationName,
        destinationAddress: destinationAddress,
        routePoints: const <LatLng>[],
        distanceMeters: 0,
        duration: '',
        baseFare: 0,
        distanceFare: 0,
        additionalPassengerFee: 0,
        baggageFee: 0,
        boundarySurcharge: 0,
        estimatedFare: 0,
        isOutsideToda: false,
        hasRoute: false,
      ),
    );

    final TodaCoverageDecision coverage;
    try {
      coverage = await TodaCoverageService.instance.classifyTrip(
        pickup: pickup,
        destination: destination,
        forceRefresh: true,
      );
    } catch (_) {
      if (!mounted || calculationGeneration != _routeCalculationGeneration) {
        return;
      }
      ref.read(bookingProvider.notifier).reset();
      _showCoverageWarning(
        'TODA coverage could not be verified. Check your connection and try again.',
      );
      return;
    }

    if (!mounted || calculationGeneration != _routeCalculationGeneration) {
      return;
    }
    if (!coverage.pickupAllowed) {
      ref.read(bookingProvider.notifier).reset();
      _showCoverageWarning(
        'Pickup is outside the configured VolTrike service areas. Choose a pickup inside a TODA coverage zone.',
      );
      return;
    }

    RouteRestrictionService.instance
      ..invalidate()
      ..clearLastConflict();
    final result = await RoutesService.computeRoute(
      origin: pickup,
      destination: destination,
    );

    if (!mounted || calculationGeneration != _routeCalculationGeneration) {
      return;
    }
    if (result == null) {
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
      isOutsideToda: coverage.isOutsideToda,
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
            isOutsideToda: coverage.isOutsideToda,

            hasRoute: true,
          ),
        );

    ref.read(bookingProvider.notifier).reset();

    if (coverage.isOutsideToda) {
      _showCoverageWarning(
        'This trip leaves the pickup TODA coverage area. The '
        '₱${fare.boundarySurcharge.toStringAsFixed(2)} outside-zone surcharge '
        'is included in the estimate.',
      );
    }
  }

  void _showCoverageWarning(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
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
    if (session.additionalPassengers >= 3) return;

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
    if (session.baggageCount >= 1) return;

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
    ref.listen<AsyncValue<FareConfiguration>>(fareConfigurationProvider, (
      previous,
      next,
    ) {
      if (!next.hasValue || previous?.valueOrNull == next.valueOrNull) {
        return;
      }
      Future<void>.microtask(() {
        if (mounted && ref.read(bookingSessionProvider).hasRoute) {
          _recalculateFare();
        }
      });
    });
    final session = ref.watch(bookingSessionProvider);

    final bookingState = ref.watch(bookingProvider);
    final routeSelectionLocked =
        bookingState == PassengerBookingState.estimatingFare ||
        bookingState == PassengerBookingState.searchingDriver;

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

                onPickupTap: routeSelectionLocked ? null : _selectPickup,

                onDestinationTap: routeSelectionLocked
                    ? null
                    : _selectDestination,

                estimatedFare: '₱${session.estimatedFare.toStringAsFixed(2)}',

                baseFare: '₱${session.baseFare.toStringAsFixed(2)}',

                distanceFare: '₱${session.distanceFare.toStringAsFixed(2)}',

                distance: session.distanceMeters == 0
                    ? '--'
                    : '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',

                eta: session.duration.isEmpty ? '--' : session.duration,

                additionalPassengers: session.additionalPassengers,

                baggageCount: session.baggageCount,

                baggageFee: '₱${session.baggageFee.toStringAsFixed(2)}',

                additionalPassengerFee:
                    '₱${session.additionalPassengerFee.toStringAsFixed(2)}',

                boundarySurcharge:
                    '₱${session.boundarySurcharge.toStringAsFixed(2)}',

                hasRoute: session.hasRoute,

                onIncreasePassengers: session.additionalPassengers < 3
                    ? _increasePassengers
                    : null,

                onDecreasePassengers: _decreasePassengers,

                onIncreaseBaggage: session.baggageCount < 1
                    ? _increaseBaggage
                    : null,

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
      final creation = await ref
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

      final breakdown = creation.fareBreakdown;
      double component(String key, double fallback) {
        final value = breakdown[key];
        return value is num && value.isFinite ? value.toDouble() : fallback;
      }

      final serverConfirmedSession = session.copyWith(
        distanceMeters: creation.distanceMeters,
        baseFare: component('baseFare', session.baseFare),
        distanceFare: component('distanceFare', session.distanceFare),
        additionalPassengerFee: component(
          'additionalPassengerFare',
          session.additionalPassengerFee,
        ),
        baggageFee: component('baggageFare', session.baggageFee),
        boundarySurcharge: component(
          'boundarySurcharge',
          session.boundarySurcharge,
        ),
        estimatedFare: creation.estimatedFare,
        isOutsideToda: creation.isOutsideToda,
      );
      ref.read(bookingSessionProvider.notifier).update(serverConfirmedSession);

      final quoteChanged =
          (creation.estimatedFare - session.estimatedFare).abs() >= 0.01 ||
          creation.distanceMeters != session.distanceMeters ||
          creation.isOutsideToda != session.isOutsideToda;
      if (quoteChanged) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Server-validated fare: '
              'â‚±${creation.estimatedFare.toStringAsFixed(2)} for '
              '${(creation.distanceMeters / 1000).toStringAsFixed(2)} km.',
            ),
          ),
        );
      }

      ref
          .read(bookingProvider.notifier)
          .update(PassengerBookingState.searchingDriver);

      context.go(AppRoutes.searchingDriver, extra: creation.bookingId);
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
