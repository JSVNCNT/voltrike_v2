import 'package:flutter/material.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

/// ===========================================================================
/// Driver Map View
///
/// Displays:
/// • Driver location
/// • Passenger pickup
/// • Destination
/// • Navigation route
///
/// This widget is presentation only.
///
/// Route calculation is handled by NavigationService.
/// ===========================================================================
class DriverMapView extends StatefulWidget {
  const DriverMapView({
    super.key,
    this.driverLocation,
    this.pickupLocation,
    this.destinationLocation,
    this.routePoints = const [],
  });

  /// Driver's live GPS location.
  final LatLng? driverLocation;

  /// Passenger pickup.
  final LatLng? pickupLocation;

  /// Trip destination.
  final LatLng? destinationLocation;

  /// Navigation polyline.
  final List<LatLng> routePoints;

  @override
  State<DriverMapView> createState() => _DriverMapViewState();
}

class _DriverMapViewState extends State<DriverMapView> {
  GoogleMapController? _controller;

  static const CameraPosition _defaultCamera = CameraPosition(
    target: LatLng(14.5995, 120.9842),
    zoom: 15,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _defaultCamera,

          myLocationEnabled: true,
          myLocationButtonEnabled: true,

          zoomControlsEnabled: false,
          compassEnabled: true,

          onMapCreated: (controller) {
            _controller = controller;
          },

          markers: {
            //--------------------------------------------------------------
            // Driver
            //--------------------------------------------------------------
            if (widget.driverLocation != null)
              Marker(
                markerId: const MarkerId('driver'),
                position: widget.driverLocation!,
                infoWindow: const InfoWindow(title: 'Your Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
              ),

            //--------------------------------------------------------------
            // Pickup
            //--------------------------------------------------------------
            if (widget.pickupLocation != null)
              Marker(
                markerId: const MarkerId('pickup'),
                position: widget.pickupLocation!,
                infoWindow: const InfoWindow(title: 'Passenger Pickup'),
              ),

            //--------------------------------------------------------------
            // Destination
            //--------------------------------------------------------------
            if (widget.destinationLocation != null)
              Marker(
                markerId: const MarkerId('destination'),
                position: widget.destinationLocation!,
                infoWindow: const InfoWindow(title: 'Destination'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
              ),
          },

          polylines: {
            if (widget.routePoints.isNotEmpty)
              Polyline(
                polylineId: const PolylineId('navigation_route'),
                points: widget.routePoints,
                width: 6,
              ),
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
