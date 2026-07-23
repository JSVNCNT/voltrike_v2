import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/driver_earnings_repository.dart';

/// ===========================================================================
/// Driver Earnings Summary
/// ===========================================================================
class DriverEarningsSummary {
  const DriverEarningsSummary({
    required this.today,
    required this.week,
    required this.month,
    required this.total,
    required this.completedTrips,
    required this.averageFare,
  });

  final double today;
  final double week;
  final double month;
  final double total;
  final int completedTrips;
  final double averageFare;
}

/// ===========================================================================
/// Repository Provider
/// ===========================================================================
final driverEarningsRepositoryProvider =
    Provider<DriverEarningsRepository>(
  (ref) => DriverEarningsRepository(),
);

/// ===========================================================================
/// Controller
/// ===========================================================================
class DriverEarningsController {
  DriverEarningsController(this._repository);

  final DriverEarningsRepository _repository;

  Future<DriverEarningsSummary> loadEarnings(
    String driverId,
  ) async {
    final today =
        await _repository.todayEarnings(driverId);

    final week =
        await _repository.weeklyEarnings(driverId);

    final month =
        await _repository.monthlyEarnings(driverId);

    final total =
        await _repository.totalEarnings(driverId);

    final trips =
        await _repository.completedTrips(driverId);

    final average =
        await _repository.averageFare(driverId);

    return DriverEarningsSummary(
      today: today,
      week: week,
      month: month,
      total: total,
      completedTrips: trips,
      averageFare: average,
    );
  }
}

/// ===========================================================================
/// Controller Provider
/// ===========================================================================
final driverEarningsControllerProvider =
    Provider<DriverEarningsController>(
  (ref) {
    return DriverEarningsController(
      ref.read(driverEarningsRepositoryProvider),
    );
  },
);

/// ===========================================================================
/// Earnings Future Provider
/// ===========================================================================
final driverEarningsProvider =
    FutureProvider.family<
        DriverEarningsSummary,
        String>(
  (ref, driverId) {
    return ref
        .read(driverEarningsControllerProvider)
        .loadEarnings(driverId);
  },
);