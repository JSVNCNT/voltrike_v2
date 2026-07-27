import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

import '../../providers/passenger_location_provider.dart';

/// ===========================================================================
/// Map View
///
/// Displays:
/// • Passenger Current Location
/// • Pickup Marker
/// • Destination Marker
/// • Route Polyline
/// • Google Traffic
/// • Future Nearby Driver Markers
/// ===========================================================================
class MapView extends ConsumerStatefulWidget {
  const MapView({
    super.key,
    this.pickup,
    this.destination,
    this.routePoints = const [],
  });

  /// Selected pickup.
  final LatLng? pickup;

  /// Selected destination.
  final LatLng? destination;

  /// Decoded route polyline.
  final List<LatLng> routePoints;

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  GoogleMapController? _mapController;

  bool _cameraInitialized = false;

  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(10.6765, 122.9509),
    zoom: 15,
  );

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(passengerLocationProvider);
    final position = location.valueOrNull;
    final currentLocation = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final pickupLocation =
        widget.pickup ?? currentLocation ?? _defaultCamera.target;

    if (_mapController != null && !_cameraInitialized) {
      _cameraInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(pickupLocation, 17),
        );
      });
    }

    final markers = <Marker>{};
    if (currentLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('current_location'),
        position: currentLocation,
        infoWindow: const InfoWindow(title: 'Current Location'),
      ));
    }
    if (widget.pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickup!,
        infoWindow: const InfoWindow(title: 'Pickup'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    if (widget.destination != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination!,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    final polylines = <Polyline>{};
    if (widget.routePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: widget.routePoints,
        width: 6,
        geodesic: true,
      ));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _defaultCamera,
          onMapCreated: (controller) => _mapController = controller,
          myLocationEnabled: currentLocation != null,
          myLocationButtonEnabled: currentLocation != null,
          trafficEnabled: true,
          compassEnabled: true,
          buildingsEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          markers: markers,
          polylines: polylines,
        ),
        if (location.isLoading)
          const Positioned(
            top: 12,
            right: 12,
            child: CircularProgressIndicator(),
          ),
        if (location.hasError)
          const Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Location unavailable. Map remains available; enable GPS to update your position.',
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
