import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ===========================================================================
/// Nearby Driver
///
/// Represents an available driver shown on the map.
/// ===========================================================================
class NearbyDriver {
  const NearbyDriver({
    required this.driverId,
    required this.name,
    required this.position,
    this.distanceMeters = 0,
    this.rating = 0,
    this.isAvailable = true,
  });

  final String driverId;

  final String name;

  final LatLng position;

  final double distanceMeters;

  final double rating;

  final bool isAvailable;

  NearbyDriver copyWith({
    String? driverId,
    String? name,
    LatLng? position,
    double? distanceMeters,
    double? rating,
    bool? isAvailable,
  }) {
    return NearbyDriver(
      driverId: driverId ?? this.driverId,
      name: name ?? this.name,
      position: position ?? this.position,
      distanceMeters:
          distanceMeters ?? this.distanceMeters,
      rating: rating ?? this.rating,
      isAvailable:
          isAvailable ?? this.isAvailable,
    );
  }
}

/// ===========================================================================
/// Nearby Driver Provider
///
/// Stores all nearby drivers.
///
/// Later this will listen to Firestore in real time.
/// ===========================================================================
class NearbyDriverNotifier
    extends StateNotifier<List<NearbyDriver>> {
  NearbyDriverNotifier() : super(const []);

  void setDrivers(
    List<NearbyDriver> drivers,
  ) {
    state = drivers;
  }

  void clear() {
    state = const [];
  }
}

final nearbyDriverProvider =
    StateNotifierProvider<
        NearbyDriverNotifier,
        List<NearbyDriver>>(
  (ref) => NearbyDriverNotifier(),
);