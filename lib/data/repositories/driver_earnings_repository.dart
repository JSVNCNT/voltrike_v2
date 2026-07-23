import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/booking.dart';

class DriverEarningsRepository {
  DriverEarningsRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _firestore.collection(FirestoreConstants.bookings);

  //==========================================================================
  // Stream of Completed Bookings
  //==========================================================================

  Stream<List<Booking>> completedBookings(String driverId) {
    return _bookings
        .where('driverId', isEqualTo: driverId)
        .where(
          'status',
          isEqualTo: BookingStatus.completed.name,
        )
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(Booking.fromFirestore).toList(),
        );
  }

  //==========================================================================
  // Total Earnings
  //==========================================================================

  Future<double> totalEarnings(String driverId) async {
    final bookings = await _loadCompleted(driverId);

    double total = 0.0;

    for (final booking in bookings) {
      total += booking.estimatedFare;
    }

    return total;
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
        total += booking.estimatedFare;
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
    ).subtract(
      Duration(days: now.weekday - 1),
    );

    double total = 0.0;

    for (final booking in bookings) {
      final completed = booking.completedAt;

      if (completed == null) continue;

      if (!completed.isBefore(weekStart)) {
        total += booking.estimatedFare;
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

      if (completed.year == now.year &&
          completed.month == now.month) {
        total += booking.estimatedFare;
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
      total += booking.estimatedFare;
    }

    return total / bookings.length;
  }

  //==========================================================================
  // Private Helper
  //==========================================================================

  Future<List<Booking>> _loadCompleted(
    String driverId,
  ) async {
    final snapshot = await _bookings
        .where(
          'driverId',
          isEqualTo: driverId,
        )
        .where(
          'status',
          isEqualTo: BookingStatus.completed.name,
        )
        .get();

    return snapshot.docs
        .map(Booking.fromFirestore)
        .toList();
  }
}