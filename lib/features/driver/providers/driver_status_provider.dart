import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ===========================================================================
/// Driver Status
/// ===========================================================================

enum DriverStatus {
  offline,
  online,
  busy,
}

/// ===========================================================================
/// Driver Status Provider
/// ===========================================================================

class DriverStatusNotifier
    extends StateNotifier<DriverStatus> {
  DriverStatusNotifier()
      : super(
          DriverStatus.offline,
        );

  void goOnline() {
    state = DriverStatus.online;
  }

  void goOffline() {
    state = DriverStatus.offline;
  }

  void goBusy() {
    state = DriverStatus.busy;
  }
}

final driverStatusProvider =
    StateNotifierProvider<
        DriverStatusNotifier,
        DriverStatus>(
  (ref) =>
      DriverStatusNotifier(),
);