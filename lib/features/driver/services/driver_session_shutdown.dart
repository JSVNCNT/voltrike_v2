import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/driver_booking_listener_provider.dart';
import '../providers/driver_location_controller_provider.dart';
import '../providers/driver_status_provider.dart';

/// Ends every driver-online subsystem before authentication is cleared.
///
/// Each cleanup is best-effort so a network failure cannot leave the local
/// foreground location service or restriction monitor running after logout.
Future<void> shutdownDriverSession(WidgetRef ref) async {
  ref.read(driverStatusProvider.notifier).goOffline();

  await _bestEffort(
    () => ref.read(driverBookingListenerProvider).stopListening(),
  );

  final locationController = ref.read(
    driverLocationControllerProvider.notifier,
  );
  if (locationController.isTracking) {
    await _bestEffort(locationController.stopTracking);
  }

  ref.invalidate(driverBookingListenerProvider);
  ref.invalidate(driverLocationControllerProvider);
  ref.invalidate(driverStatusProvider);
}

Future<void> _bestEffort(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    // Auth logout must still finish; Realtime Database onDisconnect and the
    // auth-state monitor provide a second cleanup layer.
  }
}
