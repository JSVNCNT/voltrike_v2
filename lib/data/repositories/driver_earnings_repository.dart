import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/booking.dart';

class DriverEarningsAggregate {
  const DriverEarningsAggregate({
    required this.today,
    required this.week,
    required this.month,
    required this.total,
    required this.completedTrips,
    required this.averageNetEarnings,
  });

  final double today;
  final double week;
  final double month;
  final double total;
  final int completedTrips;
  final double averageNetEarnings;
}

class DriverEarningsRepository {
  DriverEarningsRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

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
        final response = await _functions
            .httpsCallable('getDriverEarningsSummary')
            .call<Map<Object?, Object?>>();
        return _aggregateFromCallable(response.data);
      } on FirebaseFunctionsException catch (error) {
        if (!const {
          'not-found',
          'unimplemented',
          'unavailable',
          'internal',
          'deadline-exceeded',
        }.contains(error.code)) {
          rethrow;
        }
        // Compatibility for an app installed before the new callable is
        // deployed. The server aggregate becomes the normal path afterward.
      }
    }
    final bookings = await _loadCompleted(driverId);
    final current = now ?? DateTime.now();
    final dayStart = DateTime(current.year, current.month, current.day);
    final weekStart = dayStart.subtract(Duration(days: current.weekday - 1));
    final monthStart = DateTime(current.year, current.month);

    var today = 0.0;
    var week = 0.0;
    var month = 0.0;
    var total = 0.0;
    for (final booking in bookings) {
      final net = booking.driverNetEarnings;
      total += net;
      final completed = booking.completedAt;
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
      completedTrips: completed.toInt(),
      averageNetEarnings: money('averageNetEarnings'),
    );
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
