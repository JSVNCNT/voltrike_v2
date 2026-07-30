import 'package:cloud_firestore/cloud_firestore.dart';

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
  DriverEarningsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
