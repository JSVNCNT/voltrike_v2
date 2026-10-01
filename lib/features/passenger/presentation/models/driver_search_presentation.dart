import 'dart:math' as math;

import '../../../../core/config/booking_config.dart';

class DriverSearchPresentation {
  const DriverSearchPresentation._();

  static int remainingSeconds({
    required DateTime bookingCreatedAt,
    required DateTime now,
    DateTime? searchExpiresAt,
    int timeoutSeconds = BookingConfig.bookingTimeoutSeconds,
  }) {
    final deadline =
        searchExpiresAt ??
        bookingCreatedAt.add(Duration(seconds: timeoutSeconds));
    final remainingMilliseconds = deadline.difference(now).inMilliseconds;
    if (remainingMilliseconds <= 0) return 0;

    final roundedUpSeconds = (remainingMilliseconds / 1000).ceil();
    return math.min(timeoutSeconds, roundedUpSeconds);
  }

  static bool requiresHighCapacity(int additionalPassengers) {
    final totalRiders = additionalPassengers + 1;
    return totalRiders > 2;
  }

  static String searchingMessage({required int additionalPassengers}) {
    if (requiresHighCapacity(additionalPassengers)) {
      return 'Looking for an E-Trike XL nearby.';
    }
    return 'Notifying nearby VolTrike drivers.';
  }

  static String unavailableMessage({
    required int additionalPassengers,
    required bool isOutsideToda,
  }) {
    if (requiresHighCapacity(additionalPassengers)) {
      return 'No E-Trike XL rides are available right now.';
    }
    if (isOutsideToda) {
      return 'No VolTrike drivers are serving this area right now.';
    }
    return 'No nearby drivers are available right now.';
  }

  static String formatCountdown(int seconds) {
    final safeSeconds = math.max(0, seconds);
    final minutes = safeSeconds ~/ 60;
    final remainder = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}
