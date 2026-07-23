/// ===========================================================================
/// Route Result
///
/// Represents a route returned by the Google Routes API.
///
/// Used by:
/// • RoutesService
/// • FareService
/// • MapView
/// ===========================================================================
class RouteResult {
  const RouteResult({
    required this.distanceMeters,
    required this.duration,
    required this.encodedPolyline,
    this.raw,
  });

  final int distanceMeters;

  final String duration;

  final String encodedPolyline;

  final Map<String, dynamic>? raw;
}