class RouteInfo {
  final int distanceMeters;
  final double distanceKm;
  final int durationMinutes;
  final String encodedPolyline;

  const RouteInfo({
    required this.distanceMeters,
    required this.distanceKm,
    required this.durationMinutes,
    required this.encodedPolyline,
  });
}