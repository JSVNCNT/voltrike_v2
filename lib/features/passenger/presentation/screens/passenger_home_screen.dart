import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/places_service.dart';
import '../../../../core/services/polyline_service.dart';
import '../../../../core/services/routes_service.dart';
import '../../../../data/models/place_prediction.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/booking_session_provider.dart';
import '../../providers/passenger_location_provider.dart';
import '../../../../core/services/fare_service.dart';
import 'destination_search_screen.dart';
import 'searching_driver_screen.dart';
import '../widgets/home_bottom_sheet.dart';
import '../widgets/map_view.dart';

/// ===========================================================================
/// Passenger Home Screen
///
/// Main booking screen.
///
/// Flow:
///
/// Passenger Location
///       ↓
/// Destination Search
///       ↓
/// Route Calculation
///       ↓
/// Fare Estimate
///       ↓
/// Booking
/// ===========================================================================
class PassengerHomeScreen
    extends ConsumerStatefulWidget {
  const PassengerHomeScreen({
    super.key,
  });

  @override
  ConsumerState<PassengerHomeScreen>
      createState() =>
          _PassengerHomeScreenState();
}

class _PassengerHomeScreenState
    extends ConsumerState<PassengerHomeScreen> {
  //==========================================================================
  // Temporary Fare Configuration
  //
  // Later loaded from Firestore.
  //==========================================================================

  static const FareConfiguration
      _fareConfiguration =
      FareConfiguration(
    baseFare: 15,
    includedMeters: 1000,
    additionalPerMeter: 0.02,
    additionalPassengerFee: 10,
    baggageFee: 20,
    outsideTodaSurcharge: 30,
  );

  //==========================================================================
  // Select Destination
  //==========================================================================

  Future<void> _selectDestination() async {
    final PlacePrediction? prediction =
        await Navigator.push<PlacePrediction>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const DestinationSearchScreen(),
      ),
    );

    if (!mounted || prediction == null) {
      return;
    }

    final details =
        await PlacesService.getPlaceDetails(
      prediction.placeId,
    );

    if (!mounted || details == null) {
      return;
    }

    final location =
        ref.read(
      passengerLocationProvider,
    );

    if (!location.hasValue) {
      return;
    }

    final Position passenger =
        location.requireValue;

    await _calculateRoute(
      passengerLocation: LatLng(
        passenger.latitude,
        passenger.longitude,
      ),
      destination: LatLng(
        details['latitude'] as double,
        details['longitude'] as double,
      ),
      destinationName:
          details['name'] as String,
    );
  }

  //==========================================================================
  // Calculate Route
  //==========================================================================

  Future<void> _calculateRoute({
    required LatLng passengerLocation,
    required LatLng destination,
    required String destinationName,
  }) async {
    ref
        .read(
          bookingProvider.notifier,
        )
        .update(
          PassengerBookingState.estimatingFare,
        );

    final result =
        await RoutesService.computeRoute(
      origin: passengerLocation,
      destination: destination,
    );

    if (!mounted || result == null) {
      ref
          .read(
            bookingProvider.notifier,
          )
          .reset();

      return;
    }

    final routePoints =
        PolylineService.decodePolyline(
      result['encodedPolyline']
          as String,
    );

    final fare =
        FareService.calculateFare(
      config: _fareConfiguration,
      distanceMeters:
          result['distanceMeters']
              as int,
    );

    ref
        .read(
          bookingSessionProvider.notifier,
        )
        .update(
          BookingSession(
            destination: destination,
            destinationName:
                destinationName,
            routePoints:
                routePoints,
            distanceMeters:
                result['distanceMeters']
                    as int,
            duration:
                result['duration']
                    as String,
            estimatedFare:
                fare.totalFare,
            additionalPassengers: 0,
            baggageCount: 0,
            isOutsideToda: false,
            hasRoute: true,
          ),
        );

    ref
        .read(
          bookingProvider.notifier,
        )
        .reset();
  }

    //==========================================================================
  // Build
  //==========================================================================

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(
      bookingSessionProvider,
    );

    final bookingState = ref.watch(
      bookingProvider,
    );

    return Scaffold(
      appBar: const AppAppBar(
        title: 'VolTrike',
        showNotifications: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapView(
              destination:
                  session.destination,
              routePoints:
                  session.routePoints,
            ),
          ),

          Align(
            alignment:
                Alignment.bottomCenter,
            child: HomeBottomSheet(
              onDestinationTap:
                  bookingState ==
                          PassengerBookingState
                              .searchingDriver
                      ? null
                      : _selectDestination,

              estimatedFare:
                  '₱${session.estimatedFare.toStringAsFixed(2)}',

              distance:
                  session.distanceMeters == 0
                      ? '--'
                      : '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',

              eta:
                  session.duration.isEmpty
                      ? '--'
                      : session.duration,

              additionalPassengers:
                  session.additionalPassengers,

              baggageFee:
                  '₱${(_fareConfiguration.baggageFee * session.baggageCount).toStringAsFixed(2)}',

              boundarySurcharge:
                  session.isOutsideToda
                      ? '₱${_fareConfiguration.outsideTodaSurcharge.toStringAsFixed(2)}'
                      : '₱0.00',

              hasRoute:
                  session.hasRoute,

              onBookRide:
                  session.hasRoute
                      ? _bookRide
                      : null,
            ),
          ),
        ],
      ),
    );
  }

   //==========================================================================
  // Book Ride
  //==========================================================================

  Future<void> _bookRide() async {
    final session = ref.read(
      bookingSessionProvider,
    );

    if (!session.hasRoute ||
        session.destination == null) {
      return;
    }

    final location = ref.read(
      passengerLocationProvider,
    );

    if (!location.hasValue) {
      return;
    }

    final Position passenger =
        location.requireValue;

    try {
      final bookingId =
      await ref
          .read(
            bookingControllerProvider.notifier,
          )
          .createBooking(
            session: session,
            pickupLatitude:
                passenger.latitude,
            pickupLongitude:
                passenger.longitude,
            pickupAddress:
                'Current Location',
            destinationAddress:
                session.destinationName ??
                    'Destination',
          );

      if (!mounted) {
        return;
      }

      ref
          .read(
            bookingProvider.notifier,
          )
          .update(
           PassengerBookingState 
                .searchingDriver,
          );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
               SearchingDriverScreen(
            bookingId: bookingId,
               ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Booking failed: $e',
          ),
        ),
      );
    }
  }

  //==========================================================================
  // Lifecycle
  //==========================================================================

  @override
  void dispose() {
    super.dispose();
  }
}