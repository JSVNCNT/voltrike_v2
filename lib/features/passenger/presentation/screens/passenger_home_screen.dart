import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/fare_service.dart';
import '../../../../core/services/booking_quote_service.dart';
import '../../../../core/services/places_service.dart';
import '../../../../core/services/polyline_service.dart';
import '../../../../core/services/route_restriction_service.dart';
import '../../../../core/services/routes_service.dart';
import '../../../../core/services/toda_coverage_service.dart';
import '../../../../data/models/place_prediction.dart';
import '../../../../data/models/ride_type.dart';
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
  static const double _initialSheetExtent = 0.42;
  static const double _compactSheetExtent = 0.18;
  static const double _expandedSheetExtent = 0.85;

  int _routeCalculationGeneration = 0;
  bool _bookingCreationInProgress = false;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _sheetExpanded = false;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetExtentChanged);
  }

  void _onSheetExtentChanged() {
    if (!mounted || !_sheetController.isAttached) return;
    final isExpanded =
        _sheetController.size >
        (_compactSheetExtent + _expandedSheetExtent) / 2;
    if (isExpanded != _sheetExpanded) {
      setState(() => _sheetExpanded = isExpanded);
    }
  }

  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    unawaited(
      _sheetController.animateTo(
        _sheetExpanded ? _compactSheetExtent : _expandedSheetExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _sheetController
      ..removeListener(_onSheetExtentChanged)
      ..dispose();
    super.dispose();
  }

  FareConfiguration get _fareConfiguration =>
      ref.read(fareConfigurationProvider).value ?? devFareConfiguration;

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

  Future<void> _selectDestination({bool additional = false}) async {
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
          title: additional ? 'Choose Final Drop-off' : 'Choose Destination',
          hintText: additional ? 'Search final drop-off' : 'Search destination',
          searchOrigin: additional && booking.destination != null
              ? booking.destination
              : booking.pickup,
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

    final selected = LatLng(
      details['latitude'] as double,
      details['longitude'] as double,
    );
    final selectedName = details['name'] as String;
    final selectedAddress = details['address'] as String;
    if (additional) {
      ref
          .read(bookingSessionProvider.notifier)
          .updateAdditionalDestination(
            destination: selected,
            destinationName: selectedName,
            destinationAddress: selectedAddress,
          );
      final current = ref.read(bookingSessionProvider);
      if (current.destination == null) return;
      await _calculateRoute(
        pickup: current.pickup!,
        pickupName: current.pickupName ?? 'Pickup',
        pickupAddress: current.pickupAddress ?? 'Pickup',
        destination: current.destination!,
        destinationName: current.destinationName ?? 'Drop-off 1',
        destinationAddress: current.destinationAddress ?? 'Drop-off 1',
        additionalDestination: selected,
        additionalDestinationName: selectedName,
        additionalDestinationAddress: selectedAddress,
      );
      return;
    }

    await _calculateRoute(
      pickup: booking.pickup!,
      pickupName: booking.pickupName ?? 'Pickup',
      pickupAddress: booking.pickupAddress ?? booking.pickupName ?? 'Pickup',
      destination: selected,
      destinationName: selectedName,
      destinationAddress: selectedAddress,
      additionalDestination: booking.additionalDestination,
      additionalDestinationName: booking.additionalDestinationName,
      additionalDestinationAddress: booking.additionalDestinationAddress,
    );
  }

  Future<void> _addDropoff() async {
    ref.read(bookingSessionProvider.notifier).enableAdditionalDropoff();
    await _selectDestination(additional: true);
  }

  Future<void> _removeAdditionalDropoff() async {
    final notifier = ref.read(bookingSessionProvider.notifier);
    notifier.removeAdditionalDropoff();
    final session = ref.read(bookingSessionProvider);
    if (session.pickup != null && session.destination != null) {
      await _calculateRoute(
        pickup: session.pickup!,
        pickupName: session.pickupName ?? 'Pickup',
        pickupAddress: session.pickupAddress ?? 'Pickup',
        destination: session.destination!,
        destinationName: session.destinationName ?? 'Destination',
        destinationAddress: session.destinationAddress ?? 'Destination',
      );
    }
  }

  Future<void> _editPassengerNote() async {
    final current = ref.read(bookingSessionProvider).passengerNote;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PassengerNoteDialog(initialValue: current),
    );
    if (result != null && mounted) {
      ref.read(bookingSessionProvider.notifier).updatePassengerNote(result);
    }
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
    LatLng? additionalDestination,
    String? additionalDestinationName,
    String? additionalDestinationAddress,
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
        additionalDestination: additionalDestination,
        additionalDestinationName: additionalDestinationName,
        additionalDestinationAddress: additionalDestinationAddress,
        routePoints: const <LatLng>[],
        routeAdvisory: '',
        distanceMeters: 0,
        duration: '',
        baseFare: 0,
        distanceFare: 0,
        additionalPassengerFee: 0,
        baggageFee: 0,
        boundarySurcharge: 0,
        additionalDropoffFare: 0,
        estimatedFare: 0,
        isOutsideToda: false,
        goQuoteToken: '',
        clearGoQuoteExpiry: true,
        hasRoute: false,
      ),
    );

    try {
      final goQuote = await BookingQuoteService.instance.tryBookingQuote(
        pickup: pickup,
        destination: destination,
        additionalDestination: additionalDestination,
        additionalPassengers: previousSession.additionalPassengers,
        baggageCount: previousSession.baggageCount,
        rideType: previousSession.rideType,
      );
      if (!mounted || calculationGeneration != _routeCalculationGeneration) {
        return;
      }
      if (goQuote != null) {
        final routePoints = PolylineService.decodePolyline(
          goQuote.encodedPolyline,
        );
        final breakdown = goQuote.fareBreakdown;
        double component(String key) {
          final value = breakdown[key];
          return value is num && value.isFinite ? value.toDouble() : 0;
        }

        final routeAdvisory = goQuote.routePolicy.hasNotice
            ? goQuote.routePolicy.passengerMessage
            : '';
        sessionNotifier.update(
          ref
              .read(bookingSessionProvider)
              .copyWith(
                pickup: pickup,
                pickupName: pickupName,
                pickupAddress: pickupAddress,
                destination: destination,
                destinationName: destinationName,
                destinationAddress: destinationAddress,
                additionalDestination: additionalDestination,
                additionalDestinationName: additionalDestinationName,
                additionalDestinationAddress: additionalDestinationAddress,
                routePoints: routePoints,
                routeAdvisory: routeAdvisory,
                routePolicy: goQuote.routePolicy,
                distanceMeters: goQuote.distanceMeters,
                duration: goQuote.durationMinutes == null
                    ? goQuote.estimatedDuration
                    : '${goQuote.durationMinutes} mins',
                baseFare: component('baseFare'),
                distanceFare: component('distanceFare'),
                additionalPassengerFee: component('additionalPassengerFare'),
                baggageFee: component('baggageFare'),
                boundarySurcharge: component('boundarySurcharge'),
                additionalDropoffFare: component('additionalDropoffFare'),
                rideTypeFare: component('rideTypeFare'),
                estimatedFare: goQuote.estimatedFare,
                isOutsideToda: goQuote.isOutsideToda,
                goQuoteToken: goQuote.quoteToken,
                goQuoteExpiresAt: goQuote.quoteExpiresAt,
                hasRoute: true,
              ),
        );
        ref.read(bookingProvider.notifier).reset();
        if (goQuote.isOutsideToda) {
          _showCoverageWarning(
            'This trip crosses or falls outside configured TODA coverage. '
            'The â‚±${component('boundarySurcharge').toStringAsFixed(2)} '
            'Outside TODA surcharge is included in the estimate.',
          );
        }
        return;
      }
    } on GoQuoteException catch (error) {
      if (!mounted || calculationGeneration != _routeCalculationGeneration) {
        return;
      }
      ref.read(bookingProvider.notifier).reset();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } on FormatException {
      if (!mounted || calculationGeneration != _routeCalculationGeneration) {
        return;
      }
      ref.read(bookingProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The server route was invalid. Please retry.'),
        ),
      );
      return;
    } catch (_) {
      if (!mounted || calculationGeneration != _routeCalculationGeneration) {
        return;
      }
      // Do not leave the sheet permanently disabled in estimatingFare when a
      // transport-level error occurs before the Go quote client can map it.
      ref.read(bookingProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to calculate the fare right now. Check your connection and try again.',
          ),
        ),
      );
      return;
    }

    final TodaCoverageDecision coverage;
    try {
      coverage = await TodaCoverageService.instance.classifyTrip(
        pickup: pickup,
        destination: destination,
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
    RouteRestrictionService.instance.clearLastConflict();
    final endpointRestriction =
        await RouteRestrictionService.instance.bookingEndpointConflict(
          pickup,
        ) ??
        await RouteRestrictionService.instance.bookingEndpointConflict(
          destination,
        );
    if (!mounted || calculationGeneration != _routeCalculationGeneration) {
      return;
    }
    if (endpointRestriction != null) {
      ref.read(bookingProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'E-trikes cannot pick up, drop off, or travel through this '
            'restricted area. Move the pin outside the red boundary.',
          ),
        ),
      );
      return;
    }
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
                  : 'No permitted e-trike route is available for this trip.',
            ),
          ),
        );
      }

      return;
    }

    final routePoints = PolylineService.decodePolyline(result.encodedPolyline);
    final routeNotices = <String>[
      if (result.avoidedRestrictionNames.isNotEmpty)
        'Route adjusted to avoid '
            '${result.avoidedRestrictionNames.join(', ')}.',
      if (result.routePolicy.restrictionsPartiallyIgnored)
        'Highways are avoided where possible. Follow posted e-trike '
            'restrictions.',
    ];
    final routeAdvisory = routeNotices.join(' ');

    final booking = ref.read(bookingSessionProvider);

    final fare = FareService.calculateFare(
      config: _fareConfiguration,
      distanceMeters: result.distanceMeters,
      passengerCount: booking.additionalPassengers + 1,
      baggageCount: booking.baggageCount,
      isOutsideToda: coverage.isOutsideToda,
      dropoffCount: booking.dropoffCount,
      rideType: booking.rideType,
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
            routeAdvisory: routeAdvisory,
            routePolicy: result.routePolicy,
            distanceMeters: result.distanceMeters,
            duration: '${result.durationMinutes} mins',

            baseFare: fare.baseFare,
            distanceFare: fare.distanceFare,
            additionalPassengerFee: fare.additionalPassengerFee,
            baggageFee: fare.baggageFee,
            boundarySurcharge: fare.boundarySurcharge,
            additionalDropoffFare: fare.additionalDropoffFare,
            estimatedFare: fare.totalFare,
            rideTypeFare: fare.rideTypeFare,
            isOutsideToda: coverage.isOutsideToda,

            hasRoute: true,
          ),
        );

    ref.read(bookingProvider.notifier).reset();

    if (coverage.isOutsideToda) {
      _showCoverageWarning(
        coverage.status == TodaTripCoverageStatus.pickupOutside
            ? 'Pickup is outside all configured TODA coverage zones. Booking '
                  'is still allowed, and the '
                  '₱${fare.boundarySurcharge.toStringAsFixed(2)} Outside TODA '
                  'surcharge is included in the estimate.'
            : 'Pickup and destination do not share an approved TODA coverage '
                  'zone. The ₱${fare.boundarySurcharge.toStringAsFixed(2)} '
                  'Outside TODA surcharge is included in the estimate.',
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
      dropoffCount: session.dropoffCount,
      rideType: session.rideType,
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
            additionalDropoffFare: fare.additionalDropoffFare,
            estimatedFare: fare.totalFare,
            rideTypeFare: fare.rideTypeFare,
          ),
        );
  }

  //==========================================================================
  // Additional Passengers
  //==========================================================================

  void _increasePassengers() {
    final session = ref.read(bookingSessionProvider);
    if (session.additionalPassengers >= 3) return;

    final passengerCount = session.additionalPassengers + 2;
    final rideType = session.rideType.canCarry(passengerCount)
        ? session.rideType
        : RideType.eTuktuk;
    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            additionalPassengers: session.additionalPassengers + 1,
            rideType: rideType,
            goQuoteToken: '',
            clearGoQuoteExpiry: true,
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
            goQuoteToken: '',
            clearGoQuoteExpiry: true,
          ),
        );

    _recalculateFare();
  }

  void _selectRideType(RideType rideType) {
    final session = ref.read(bookingSessionProvider);
    final passengerCount = session.additionalPassengers + 1;
    final config = _fareConfiguration;
    if (!rideType.canCarry(passengerCount) ||
        !config.isRideTypeEnabled(rideType) ||
        rideType == session.rideType) {
      return;
    }
    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            rideType: rideType,
            goQuoteToken: '',
            clearGoQuoteExpiry: true,
          ),
        );
    _recalculateFare();
  }

  RideType _availableRideType(
    BookingSession session,
    FareConfiguration config,
  ) {
    final passengerCount = session.additionalPassengers + 1;
    if (session.rideType.canCarry(passengerCount) &&
        config.isRideTypeEnabled(session.rideType)) {
      return session.rideType;
    }
    return RideType.values.firstWhere(
      (type) => type.canCarry(passengerCount) && config.isRideTypeEnabled(type),
      orElse: () => session.rideType,
    );
  }

  //==========================================================================
  // Baggage
  //==========================================================================

  void _increaseBaggage() {
    final session = ref.read(bookingSessionProvider);
    if (session.baggageCount >= 1) return;

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            baggageCount: session.baggageCount + 1,
            goQuoteToken: '',
            clearGoQuoteExpiry: true,
          ),
        );

    _recalculateFare();
  }

  void _decreaseBaggage() {
    final session = ref.read(bookingSessionProvider);

    if (session.baggageCount == 0) {
      return;
    }

    ref
        .read(bookingSessionProvider.notifier)
        .update(
          session.copyWith(
            baggageCount: session.baggageCount - 1,
            goQuoteToken: '',
            clearGoQuoteExpiry: true,
          ),
        );

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
      if (!next.hasValue || previous?.value == next.value) {
        return;
      }
      Future<void>.microtask(() {
        if (mounted) {
          final session = ref.read(bookingSessionProvider);
          final config = next.value!;
          final availableType = _availableRideType(session, config);
          if (availableType != session.rideType) {
            ref
                .read(bookingSessionProvider.notifier)
                .update(
                  session.copyWith(
                    rideType: availableType,
                    goQuoteToken: '',
                    clearGoQuoteExpiry: true,
                  ),
                );
          }
        }
        if (mounted && ref.read(bookingSessionProvider).hasRoute) {
          _recalculateFare();
        }
      });
    });
    final session = ref.watch(bookingSessionProvider);
    final fareConfiguration =
        ref.watch(fareConfigurationProvider).value ?? devFareConfiguration;
    final passengerCount = session.additionalPassengers + 1;
    double fareFor(RideType rideType) => session.hasRoute
        ? FareService.calculateFare(
            config: fareConfiguration,
            distanceMeters: session.distanceMeters,
            passengerCount: passengerCount,
            baggageCount: session.baggageCount,
            isOutsideToda: session.isOutsideToda,
            dropoffCount: session.dropoffCount,
            rideType: rideType,
          ).totalFare
        : 0;
    final selectedRideIsAvailable =
        session.rideType.canCarry(passengerCount) &&
        fareConfiguration.isRideTypeEnabled(session.rideType);

    final bookingState = ref.watch(bookingProvider);
    final routeSelectionLocked =
        _bookingCreationInProgress ||
        bookingState == PassengerBookingState.estimatingFare ||
        bookingState == PassengerBookingState.searchingDriver;

    return Scaffold(
      appBar: const AppAppBar(title: 'Passenger'),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapView(
              pickup: session.pickup,
              destination: session.finalDestination,
              intermediateDestination: session.additionalDestination == null
                  ? null
                  : session.destination,
              routePoints: session.routePoints,
            ),
          ),

          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: _initialSheetExtent,
            minChildSize: _compactSheetExtent,
            maxChildSize: _expandedSheetExtent,
            builder: (context, scrollController) {
              return HomeBottomSheet(
                scrollController: scrollController,
                isExpanded: _sheetExpanded,
                onToggleExpanded: _toggleSheet,

                pickup: session.pickupName ?? 'Select pickup',

                destination: session.destinationName ?? 'Where are you going?',
                additionalDropoffEnabled: session.additionalDropoffEnabled,
                additionalDestination: session.additionalDestinationName,

                onPickupTap: routeSelectionLocked ? null : _selectPickup,

                onDestinationTap: routeSelectionLocked
                    ? null
                    : _selectDestination,
                onAddDropoff:
                    routeSelectionLocked || session.destination == null
                    ? null
                    : _addDropoff,
                onAdditionalDestinationTap: routeSelectionLocked
                    ? null
                    : () => _selectDestination(additional: true),
                onRemoveAdditionalDropoff: routeSelectionLocked
                    ? null
                    : _removeAdditionalDropoff,
                onEditNote: routeSelectionLocked ? null : _editPassengerNote,

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
                additionalDropoffFare:
                    '₱${session.additionalDropoffFare.toStringAsFixed(2)}',
                dropoffCount: session.dropoffCount,

                isOutsideToda: session.isOutsideToda,

                routeAdvisory: session.routeAdvisory,
                rideTypeFare: '₱${session.rideTypeFare.toStringAsFixed(2)}',
                selectedRideType: session.rideType,
                eTrikeFare: '₱${fareFor(RideType.eTrike).toStringAsFixed(2)}',
                eTuktukFare: '₱${fareFor(RideType.eTuktuk).toStringAsFixed(2)}',
                eTrikeEnabled: fareConfiguration.eTrikeEnabled,
                eTuktukEnabled: fareConfiguration.eTuktukEnabled,
                onRideTypeSelected: routeSelectionLocked
                    ? null
                    : _selectRideType,

                hasRoute: session.hasRoute,

                onIncreasePassengers: session.additionalPassengers < 3
                    ? _increasePassengers
                    : null,

                onDecreasePassengers: _decreasePassengers,

                onIncreaseBaggage: session.baggageCount < 1
                    ? _increaseBaggage
                    : null,

                onDecreaseBaggage: _decreaseBaggage,

                onBookRide:
                    session.hasRoute &&
                        selectedRideIsAvailable &&
                        !_bookingCreationInProgress
                    ? _bookRide
                    : null,
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
    if (_bookingCreationInProgress) return;
    var session = ref.read(bookingSessionProvider);

    if (!session.hasRoute ||
        session.pickup == null ||
        session.destination == null) {
      return;
    }

    setState(() => _bookingCreationInProgress = true);
    try {
      final refreshedSession = await _confirmCurrentQuote(session);
      if (refreshedSession == null || !mounted) return;
      session = refreshedSession;

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

      var confirmedRoutePoints = session.routePoints;
      if (creation.authoritativeRoutePolyline.isNotEmpty) {
        try {
          confirmedRoutePoints = PolylineService.decodePolyline(
            creation.authoritativeRoutePolyline,
          );
        } on FormatException {
          // The durable booking remains valid; retain the already-rendered
          // client route if a malformed legacy response is encountered.
        }
      }
      final serverRouteAdvisory = creation.avoidedRouteRestrictionNames.isEmpty
          ? creation.routePolicy.hasNotice
                ? creation.routePolicy.passengerMessage
                : session.routeAdvisory
          : 'Server route avoids '
                '${creation.avoidedRouteRestrictionNames.join(', ')}. '
                'Follow the route shown in the app.';
      final serverConfirmedSession = session.copyWith(
        routePoints: confirmedRoutePoints,
        distanceMeters: creation.distanceMeters,
        routeAdvisory: serverRouteAdvisory,
        routePolicy: creation.routePolicy,
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
        additionalDropoffFare: component(
          'additionalDropoffFare',
          session.additionalDropoffFare,
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
        if (creation.isOutsideToda != session.isOutsideToda) {
          _showCoverageWarning(
            creation.isOutsideToda
                ? 'Server validation confirmed this is an Outside TODA trip. '
                      'The ₱${serverConfirmedSession.boundarySurcharge.toStringAsFixed(2)} '
                      'surcharge is included in the '
                      '₱${creation.estimatedFare.toStringAsFixed(2)} fare.'
                : 'Server validation confirmed pickup and destination share a '
                      'TODA coverage zone. No Outside TODA surcharge applies.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Server-validated fare: '
                '₱${creation.estimatedFare.toStringAsFixed(2)} for '
                '${(creation.distanceMeters / 1000).toStringAsFixed(2)} km.',
              ),
            ),
          );
        }
      }

      ref
          .read(bookingProvider.notifier)
          .update(PassengerBookingState.searchingDriver);

      context.go(
        AppRoutes.withBookingId(AppRoutes.searchingDriver, creation.bookingId),
        extra: creation.bookingId,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _bookingCreationInProgress = false);
      }
    }
  }

  /// Refreshes an expired/invalidated quote and obtains explicit consent when
  /// any user-visible price or coverage fact changed. No booking is created
  /// until this completes successfully.
  Future<BookingSession?> _confirmCurrentQuote(BookingSession session) async {
    final expiresAt = session.goQuoteExpiresAt;
    final quoteIsUsable =
        session.goQuoteToken.trim().isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 15)));
    if (quoteIsUsable) return session;

    final quote = await BookingQuoteService.instance.tryBookingQuote(
      pickup: session.pickup!,
      destination: session.destination!,
      additionalDestination: session.additionalDestination,
      additionalPassengers: session.additionalPassengers,
      baggageCount: session.baggageCount,
      rideType: session.rideType,
    );
    if (quote == null || quote.quoteToken.trim().isEmpty) {
      throw const GoQuoteException(
        'The fare could not be confirmed. Check your connection and retry.',
      );
    }

    double component(String key) {
      final value = quote.fareBreakdown[key];
      return value is num && value.isFinite ? value.toDouble() : 0;
    }

    List<LatLng> routePoints = session.routePoints;
    try {
      routePoints = PolylineService.decodePolyline(quote.encodedPolyline);
    } on FormatException {
      throw const GoQuoteException(
        'The confirmed route was invalid. Please calculate the trip again.',
      );
    }
    final refreshed = session.copyWith(
      routePoints: routePoints,
      routeAdvisory: quote.routePolicy.hasNotice
          ? quote.routePolicy.passengerMessage
          : '',
      routePolicy: quote.routePolicy,
      distanceMeters: quote.distanceMeters,
      duration: quote.durationMinutes == null
          ? quote.estimatedDuration
          : '${quote.durationMinutes} mins',
      baseFare: component('baseFare'),
      distanceFare: component('distanceFare'),
      additionalPassengerFee: component('additionalPassengerFare'),
      baggageFee: component('baggageFare'),
      boundarySurcharge: component('boundarySurcharge'),
      additionalDropoffFare: component('additionalDropoffFare'),
      rideTypeFare: component('rideTypeFare'),
      estimatedFare: quote.estimatedFare,
      isOutsideToda: quote.isOutsideToda,
      goQuoteToken: quote.quoteToken,
      goQuoteExpiresAt: quote.quoteExpiresAt,
      hasRoute: true,
    );
    ref.read(bookingSessionProvider.notifier).update(refreshed);

    final changed =
        (refreshed.estimatedFare - session.estimatedFare).abs() >= 0.01 ||
        refreshed.distanceMeters != session.distanceMeters ||
        refreshed.isOutsideToda != session.isOutsideToda;
    if (!changed || !mounted) return refreshed;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.receipt_long_rounded),
        title: const Text('Fare updated'),
        content: Text(
          'The current server-confirmed fare is '
          '₱${refreshed.estimatedFare.toStringAsFixed(2)} for '
          '${(refreshed.distanceMeters / 1000).toStringAsFixed(2)} km. '
          '${refreshed.isOutsideToda ? 'The Outside TODA surcharge is included. ' : ''}'
          'Do you want to request the ride at this fare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Review trip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Request ride'),
          ),
        ],
      ),
    );
    return accepted == true ? refreshed : null;
  }
}

class _PassengerNoteDialog extends StatefulWidget {
  const _PassengerNoteDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_PassengerNoteDialog> createState() => _PassengerNoteDialogState();
}

class _PassengerNoteDialogState extends State<_PassengerNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note for your driver'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Example: Waiting by the blue gate',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save note'),
        ),
      ],
    );
  }
}
