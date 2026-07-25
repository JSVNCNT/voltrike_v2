import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/navigation_service.dart';
import '../../../../data/models/booking.dart';
import '../models/ride_tracking_state.dart';

/// Shared map/tracking controller used by passenger and driver ride screens.
class RideTrackingController extends StateNotifier<RideTrackingState> {
  RideTrackingController({NavigationService? navigation})
      : _navigation = navigation ?? NavigationService.instance,
        super(const RideTrackingState());

  final NavigationService _navigation;
  Booking? _booking;

  void setBooking(Booking booking) {
    _booking = booking;
    state = state.copyWith(
      markers: _markers(booking, null),
      polylines: _polylines(state.routePoints),
    );
  }

  void setDriverLocation(LatLng? location) {
    final booking = _booking;
    if (booking == null) return;

    state = state.copyWith(
      markers: _markers(booking, location),
    );
  }

  Future<void> loadRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    state = state.copyWith(isLoadingRoute: true);

    final route = await _navigation.computeRouteInfo(
      origin: origin,
      destination: destination,
    );

    if (route == null) {
      state = state.copyWith(isLoadingRoute: false);
      return;
    }

    final points = _navigation.decodePolyline(route.encodedPolyline);
    state = state.copyWith(
      routePoints: points,
      polylines: _polylines(points),
      distanceText: '${route.distanceKm.toStringAsFixed(1)} km',
      durationText: '${route.durationMinutes} mins',
      isLoadingRoute: false,
    );
  }

  void setFollowingDriver(bool value) {
    state = state.copyWith(isFollowingDriver: value);
  }

  void clear() {
    _booking = null;
    state = const RideTrackingState();
  }

  Set<Marker> _markers(Booking booking, LatLng? driverLocation) {
    return {
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
    };
  }

  Set<Polyline> _polylines(List<LatLng> points) {
    if (points.isEmpty) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('ride-route'),
        points: points,
        width: 5,
      ),
    };
  }
}
