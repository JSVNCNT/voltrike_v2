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
    required this.completedTripAmount,
    required this.completedTrips,
    required this.averageFare,
  });

  final double today;
  final double week;
  final double month;
  final double total;
  final double completedTripAmount;
  final int completedTrips;
  final double averageFare;
}

/// ===========================================================================
/// Repository Provider
/// ===========================================================================
final driverEarningsRepositoryProvider = Provider<DriverEarningsRepository>(
  (ref) => DriverEarningsRepository(),
);

/// ===========================================================================
/// Controller
/// ===========================================================================
class DriverEarningsController {
  DriverEarningsController(this._repository);

  final DriverEarningsRepository _repository;

  Future<DriverEarningsSummary> loadEarnings(String driverId) async {
    final aggregate = await _repository.loadAggregate(driverId);

    return DriverEarningsSummary(
      today: aggregate.today,
      week: aggregate.week,
      month: aggregate.month,
      total: aggregate.total,
      completedTripAmount: aggregate.completedTripAmount,
      completedTrips: aggregate.completedTrips,
      averageFare: aggregate.averageNetEarnings,
    );
  }
}

/// ===========================================================================
/// Controller Provider
/// ===========================================================================
final driverEarningsControllerProvider = Provider<DriverEarningsController>((
  ref,
) {
  return DriverEarningsController(ref.read(driverEarningsRepositoryProvider));
});

/// ===========================================================================
/// Earnings Future Provider
/// ===========================================================================
final driverEarningsProvider =
    FutureProvider.family<DriverEarningsSummary, String>((ref, driverId) {
      return ref.read(driverEarningsControllerProvider).loadEarnings(driverId);
    });
