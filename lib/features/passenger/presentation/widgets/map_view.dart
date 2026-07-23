import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../providers/passenger_location_provider.dart';

/// ===========================================================================
/// Map View
///
/// Displays:
/// • Passenger Location
/// • Destination Marker
/// • Route Polyline
/// • Google Traffic
/// • Future Nearby Driver Markers
/// ===========================================================================
class MapView extends ConsumerStatefulWidget {
  const MapView({
    super.key,
    this.destination,
    this.routePoints = const [],
  });

  /// Selected destination.
  final LatLng? destination;

  /// Decoded route polyline points.
  final List<LatLng> routePoints;

  @override
  ConsumerState<MapView> createState() =>
      _MapViewState();
}

class _MapViewState
    extends ConsumerState<MapView> {
  GoogleMapController? _mapController;

  bool _cameraInitialized = false;

  static const CameraPosition _defaultCamera =
      CameraPosition(
    target: LatLng(
      14.5995,
      120.9842,
    ),
    zoom: 15,
  );

  @override
  Widget build(BuildContext context) {
    final location =
        ref.watch(
      passengerLocationProvider,
    );

    return location.when(
      loading: () {
        return const Center(
          child:
              CircularProgressIndicator(),
        );
      },
      error: (error, _) {
        return Center(
          child: Text(
            error.toString(),
          ),
        );
      },
      data: (Position position) {
        final passengerLocation =
            LatLng(
          position.latitude,
          position.longitude,
        );

        //--------------------------------------------------------------
        // Move camera only once after GPS is obtained.
        //--------------------------------------------------------------

        if (_mapController != null &&
            !_cameraInitialized) {
          _cameraInitialized = true;

          WidgetsBinding.instance
              .addPostFrameCallback((_) {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                passengerLocation,
                17,
              ),
            );
          });
        }

        //--------------------------------------------------------------
        // Passenger + Destination Markers
        //--------------------------------------------------------------

        final markers = <Marker>{
          Marker(
            markerId:
                const MarkerId(
              'passenger',
            ),
            position:
                passengerLocation,
            infoWindow:
                const InfoWindow(
              title: 'Your Location',
            ),
          ),
        };

        if (widget.destination != null) {
          markers.add(
            Marker(
              markerId:
                  const MarkerId(
                'destination',
              ),
              position:
                  widget.destination!,
              infoWindow:
                  const InfoWindow(
                title: 'Destination',
              ),
            ),
          );
        }

        //--------------------------------------------------------------
        // Route Polyline
        //--------------------------------------------------------------

        final polylines = <Polyline>{};

        if (widget.routePoints.isNotEmpty) {
          polylines.add(
            Polyline(
              polylineId:
                  const PolylineId(
                'route',
              ),
              points:
                  widget.routePoints,
              width: 6,
              geodesic: true,
            ),
          );
        }

        return GoogleMap(
          initialCameraPosition:
              _defaultCamera,

          onMapCreated:
              (GoogleMapController controller) {
            _mapController =
                controller;
          },

          myLocationEnabled: true,

          myLocationButtonEnabled: true,

          trafficEnabled: true,

          compassEnabled: true,

          buildingsEnabled: true,

          mapToolbarEnabled: false,

          zoomControlsEnabled: false,

          markers: markers,

          polylines: polylines,
        );
      },
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}