import 'package:geolocator/geolocator.dart';

class NavigationConfig {
  const NavigationConfig._();

  //==========================================================================
  // GPS
  //==========================================================================

  static const LocationAccuracy
      currentLocationAccuracy =
      LocationAccuracy.high;

  static const LocationAccuracy
      navigationAccuracy =
      LocationAccuracy.best;

  static const int distanceFilter = 10;

  //==========================================================================
  // Route Refresh
  //==========================================================================

  static const int refreshRouteSeconds = 15;

  static const bool trafficAware = true;

  static const bool alternateRoutes = true;

  static const bool snapToRoad = true;
}