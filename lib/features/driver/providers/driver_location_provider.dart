import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

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
