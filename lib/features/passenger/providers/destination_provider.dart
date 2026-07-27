import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

/// ===========================================================================
/// Destination Provider
///
/// Stores the selected destination.
///
/// Later this will be populated from:
/// • Google Places API
/// • Map Selection
/// ===========================================================================
class DestinationNotifier
    extends StateNotifier<LatLng?> {
  DestinationNotifier() : super(null);

  void setDestination(
    LatLng destination,
  ) {
    state = destination;
  }

  void clear() {
    state = null;
  }
}

final destinationProvider =
    StateNotifierProvider<
        DestinationNotifier,
        LatLng?>(
  (ref) => DestinationNotifier(),
);
