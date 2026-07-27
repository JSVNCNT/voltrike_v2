import 'package:voltrike_v2/core/maps/voltrike_map.dart';

class GoogleMapsConfig {
  const GoogleMapsConfig._();

  //==========================================================================
  // Camera
  //==========================================================================

  static const double defaultZoom = 16;

  static const double minZoom = 5;

  static const double maxZoom = 21;

  static const CameraPosition initialCamera =
      CameraPosition(
        target: LatLng(
          10.6765,
          122.9509,
        ), // Bacolod City
        zoom: defaultZoom,
      );

  //==========================================================================
  // UI
  //==========================================================================

  static const bool myLocationEnabled = true;

  static const bool myLocationButtonEnabled =
      true;

  static const bool compassEnabled = true;

  static const bool trafficEnabled = true;

  static const bool buildingsEnabled = true;

  static const bool zoomControlsEnabled =
      false;

  static const bool zoomGesturesEnabled =
      true;

  static const bool rotateGesturesEnabled =
      true;

  static const bool tiltGesturesEnabled =
      true;

  static const bool mapToolbarEnabled =
      false;
}
