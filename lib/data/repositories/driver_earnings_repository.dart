import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/voltrike_api.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/booking.dart';

class DriverEarningsAggregate {
  const DriverEarningsAggregate({
    required this.today,
    required this.week,
    required this.month,
    required this.total,
    required this.completedTripAmount,
    required this.completedTrips,
    required this.averageNetEarnings,
  });

  final double today;
  final double week;
  final double month;
  final double total;
  final double completedTripAmount;
  final int completedTrips;
  final double averageNetEarnings;
}

class DriverEarningsRepository {
  DriverEarningsRepository({FirebaseFirestore? firestore, VoltrikeApi? api})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _api = api ?? VoltrikeApi.instance;

  final FirebaseFirestore _firestore;
  final VoltrikeApi _api;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection(FirestoreConstants.bookings);

  //==========================================================================
  // Stream of Completed Bookings
  //==========================================================================

  Stream<List<Booking>> completedBookings(String driverId) {
    return _bookings
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: BookingStatus.completed.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Booking.fromFirestore).toList());
  }

  //==========================================================================
  // Total Earnings
  //==========================================================================

  Future<double> totalEarnings(String driverId) async {
    final bookings = await _loadCompleted(driverId);
    return bookings.fold<double>(
      0,
      (total, booking) => total + booking.driverNetEarnings,
    );
  }

  //==========================================================================
  // Today's Earnings
  //==========================================================================

  Future<double> todayEarnings(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    final now = DateTime.now();

    double total = 0.0;

    for (final booking in bookings) {
      final completed = booking.completedAt;

      if (completed == null) continue;

      if (completed.year == now.year &&
          completed.month == now.month &&
          completed.day == now.day) {
        total += booking.driverNetEarnings;
      }
    }

    return total;
  }

  //==========================================================================
  // Weekly Earnings
  //==========================================================================

  Future<double> weeklyEarnings(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    final now = DateTime.now();

    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));

    double total = 0.0;

    for (final booking in bookings) {
      final completed = booking.completedAt;

      if (completed == null) continue;

      if (!completed.isBefore(weekStart)) {
        total += booking.driverNetEarnings;
      }
    }

    return total;
  }

  //==========================================================================
  // Monthly Earnings
  //==========================================================================

  Future<double> monthlyEarnings(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    final now = DateTime.now();

    double total = 0.0;

    for (final booking in bookings) {
      final completed = booking.completedAt;

      if (completed == null) continue;

      if (completed.year == now.year && completed.month == now.month) {
        total += booking.driverNetEarnings;
      }
    }

    return total;
  }

  //==========================================================================
  // Completed Trips
  //==========================================================================

  Future<int> completedTrips(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    return bookings.length;
  }

  //==========================================================================
  // Average Fare
  //==========================================================================

  Future<double> averageFare(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    if (bookings.isEmpty) {
      return 0.0;
    }

    double total = 0.0;

    for (final booking in bookings) {
      total += booking.driverNetEarnings;
    }

    return total / bookings.length;
  }

  /// Loads completed rides once, then derives every earnings period from the
  /// same authoritative driver-net snapshot.
  Future<DriverEarningsAggregate> loadAggregate(
    String driverId, {
    DateTime? now,
  }) async {
    if (now == null) {
      try {
        final response = await _api.operation(
          'getDriverEarningsSummary',
          const <String, dynamic>{},
        );
        final aggregate = _aggregateFromCallable(response);
        if (_hasCompletedTripAmount(response)) return aggregate;

        // Older Cloud Run revisions did not return the gross completed-fare
        // total. Keep installed/private-test apps compatible while the new
        // revision rolls out by deriving only that missing value locally.
        final bookings = await _loadCompleted(driverId);
        return DriverEarningsAggregate(
          today: aggregate.today,
          week: aggregate.week,
          month: aggregate.month,
          total: aggregate.total,
          completedTripAmount: _completedTripAmount(bookings),
          completedTrips: aggregate.completedTrips,
          averageNetEarnings: aggregate.averageNetEarnings,
        );
      } on VoltrikeApiException catch (error) {
        if (!const {
          'not_found',
          'unavailable',
          'internal',
        }.contains(error.code)) {
          rethrow;
        }
        // Compatibility for an app installed before the new callable is
        // deployed. The server aggregate becomes the normal path afterward.
      }
    }
    final bookings = await _loadCompleted(driverId);
    final current = now ?? _manilaTime(DateTime.now());
    final dayStart = DateTime(current.year, current.month, current.day);
    final weekStart = dayStart.subtract(Duration(days: current.weekday - 1));
    final monthStart = DateTime(current.year, current.month);

    var today = 0.0;
    var week = 0.0;
    var month = 0.0;
    var total = 0.0;
    var completedTripAmount = 0.0;
    for (final booking in bookings) {
      final net = booking.driverNetEarnings;
      total += net;
      completedTripAmount += booking.grossFare;
      final completed = booking.completedAt == null
          ? null
          : _manilaTime(booking.completedAt!);
      if (completed == null) continue;
      if (!completed.isBefore(dayStart)) today += net;
      if (!completed.isBefore(weekStart)) week += net;
      if (!completed.isBefore(monthStart)) month += net;
    }

    return DriverEarningsAggregate(
      today: today,
      week: week,
      month: month,
      total: total,
      completedTripAmount: completedTripAmount,
      completedTrips: bookings.length,
      averageNetEarnings: bookings.isEmpty ? 0 : total / bookings.length,
    );
  }

  DriverEarningsAggregate _aggregateFromCallable(Object? value) {
    final data = value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : const <String, dynamic>{};
    double money(String key) {
      final value = data[key];
      if (value is num && value.isFinite) return value.toDouble();
      throw FormatException('Earnings summary is missing $key.');
    }

    final completed = data['completedTrips'];
    if (completed is! num || !completed.isFinite || completed < 0) {
      throw const FormatException(
        'Earnings summary has an invalid trip count.',
      );
    }
    return DriverEarningsAggregate(
      today: money('today'),
      week: money('week'),
      month: money('month'),
      total: money('total'),
      completedTripAmount: data['completedTripAmount'] is num
          ? money('completedTripAmount')
          : money('total'),
      completedTrips: completed.toInt(),
      averageNetEarnings: money('averageNetEarnings'),
    );
  }

  bool _hasCompletedTripAmount(Object? value) {
    if (value is! Map) return false;
    final amount = value['completedTripAmount'];
    return amount is num && amount.isFinite;
  }

  double _completedTripAmount(List<Booking> bookings) {
    return bookings.fold<double>(
      0,
      (total, booking) => total + booking.grossFare,
    );
  }

  DateTime _manilaTime(DateTime value) {
    return value.toUtc().add(const Duration(hours: 8));
  }

  //==========================================================================
  // Private Helper
  //==========================================================================

  Future<List<Booking>> _loadCompleted(String driverId) async {
    final snapshot = await _bookings
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: BookingStatus.completed.name)
        .get();

    return snapshot.docs.map(Booking.fromFirestore).toList();
  }
}
