import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'driver_location_controller_provider.dart';

/// Single UI projection of the driver location session.
///
/// GPS ownership, RTDB publication, heartbeat, lifecycle recovery, and
/// disposal all remain in [driverLocationControllerProvider].
final driverLocationProvider = Provider<LatLng?>(
  (ref) => ref.watch(
    driverLocationControllerProvider.select((state) => state.location),
  ),
);
