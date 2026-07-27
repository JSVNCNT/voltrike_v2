import 'package:geolocator/geolocator.dart';

class NavigationConfig {
  const NavigationConfig._();

  /// Android-only development pilot for the Google Navigation SDK.
  ///
  /// Disable without changing source code by running with:
  /// `--dart-define=VOLTRIKE_IN_APP_NAVIGATION=false`.
  static const bool inAppTurnByTurnEnabled = bool.fromEnvironment(
    'VOLTRIKE_IN_APP_NAVIGATION',
    defaultValue: true,
  );

  //==========================================================================
  // GPS
  //==========================================================================

  static const LocationAccuracy currentLocationAccuracy = LocationAccuracy.high;

  static const LocationAccuracy navigationAccuracy = LocationAccuracy.best;

  static const int distanceFilter = 10;

  //==========================================================================
  // Route Refresh
  //==========================================================================

  static const int refreshRouteSeconds = 15;

  static const bool trafficAware = true;

  static const bool alternateRoutes = true;

  static const bool snapToRoad = true;
}
