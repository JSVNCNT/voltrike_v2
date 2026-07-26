class DistanceFormatter {
  const DistanceFormatter._();

  /// Formats a distance for compact, user-facing labels.
  ///
  /// Distances below one kilometre are rounded to the nearest metre. Distances
  /// from one kilometre onward use one decimal place.
  static String compactMeters(num meters) {
    final safeMeters = meters.isFinite
        ? meters.toDouble().clamp(0, double.infinity)
        : 0.0;
    if (safeMeters < 1000) {
      return '${safeMeters.round()} m';
    }
    return '${(safeMeters / 1000).toStringAsFixed(1)} km';
  }
}
