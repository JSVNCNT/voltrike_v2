import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';

/// ===========================================================================
/// Passenger Dashboard
///
/// Overview screen for the passenger.
///
/// Displays:
/// • Welcome
/// • Ride Statistics
/// • Spending Summary
/// • Recent Trip
/// • Recent Activity
/// ===========================================================================
class PassengerDashboardScreen extends ConsumerWidget {
  const PassengerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = AuthRepository();

    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Passenger not signed in.')),
      );
    }

    final bookings = BookingRepository().bookingsForPassenger(user.uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: StreamBuilder<List<Booking>>(
        stream: bookings,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final List<Booking> trips = snapshot.data ?? <Booking>[];

          Booking? recentTrip;

          if (trips.isNotEmpty) {
            trips.sort(
              (Booking a, Booking b) => b.createdAt.compareTo(a.createdAt),
            );

            recentTrip = trips.first;
          }

          int completedTrips = 0;
          int pendingTrips = 0;
          int cancelledTrips = 0;

          double totalSpent = 0;

          for (final booking in trips) {
            switch (booking.status) {
              case BookingStatus.completed:
                completedTrips++;
                totalSpent += booking.amountDue;
                break;

              case BookingStatus.pending:
                pendingTrips++;
                break;

              case BookingStatus.cancelled:
                cancelledTrips++;
                break;

              default:
                break;
            }
          }

          final double averageFare = completedTrips == 0
              ? 0
              : totalSpent / completedTrips;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  //----------------------------------------------------------------
                  // Welcome Card
                  //----------------------------------------------------------------
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome Back',
                            style: TextStyle(color: Colors.grey),
                          ),

                          const SizedBox(height: 8),

                          FutureBuilder(
                            future: UserRepository().getUser(user.uid),
                            builder: (context, snapshot) => Text(
                              snapshot.data?.fullName ??
                                  user.displayName ??
                                  user.email ??
                                  'Passenger',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  _PassengerRatingsCard(passengerId: user.uid, trips: trips),

                  const SizedBox(height: 20),

                  //----------------------------------------------------------------
                  // Ride Statistics
                  //----------------------------------------------------------------
                  const Text(
                    'Ride Statistics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.route,
                                  color: Colors.blue,
                                  size: 36,
                                ),

                                const SizedBox(height: 12),

                                Text(
                                  trips.length.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text('Total Trips'),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 36,
                                ),

                                const SizedBox(height: 12),

                                Text(
                                  completedTrips.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text('Completed'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  color: Colors.orange,
                                  size: 36,
                                ),

                                const SizedBox(height: 12),

                                Text(
                                  pendingTrips.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text('Pending'),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 36,
                                ),

                                const SizedBox(height: 12),

                                Text(
                                  cancelledTrips.toString(),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text('Cancelled'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  //----------------------------------------------------------------
                  // Spending Summary
                  //----------------------------------------------------------------
                  const Text(
                    'Spending Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.payments,
                              color: Colors.green,
                            ),
                            title: const Text('Total Spent'),
                            trailing: Text(
                              '₱${totalSpent.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),

                          const Divider(),

                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.bar_chart,
                              color: Colors.blue,
                            ),
                            title: const Text('Average Fare'),
                            trailing: Text(
                              '₱${averageFare.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  //----------------------------------------------------------------
                  // Recent Trip
                  //----------------------------------------------------------------
                  const Text(
                    'Recent Trip',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  if (recentTrip == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No trips yet.')),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.my_location,
                                color: Colors.green,
                              ),
                              title: const Text('Pickup'),
                              subtitle: Text(recentTrip.pickupAddress),
                            ),

                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                              ),
                              title: const Text('Destination'),
                              subtitle: Text(recentTrip.destinationAddress),
                            ),

                            const Divider(),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Chip(label: Text(recentTrip.status.name)),
                                Text(
                                  '₱${recentTrip.amountDue.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Colors.grey,
                                ),

                                const SizedBox(width: 8),

                                Text(
                                  recentTrip.createdAt
                                      .toLocal()
                                      .toString()
                                      .split('.')
                                      .first,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                            if (recentTrip.driverId != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (recentTrip.status !=
                                          BookingStatus.completed &&
                                      recentTrip.status !=
                                          BookingStatus.cancelled)
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => context.push(
                                          AppRoutes.driverTracking,
                                          extra: recentTrip!.bookingId,
                                        ),
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text('Open current trip'),
                                      ),
                                    ),
                                  if (recentTrip.status !=
                                          BookingStatus.completed &&
                                      recentTrip.status !=
                                          BookingStatus.cancelled)
                                    const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => showRideReportDialog(
                                        context: context,
                                        booking: recentTrip!,
                                        reporterIsDriver: false,
                                      ),
                                      icon: const Icon(
                                        Icons.report_problem_outlined,
                                      ),
                                      label: const Text('Report'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  //----------------------------------------------------------------
                  // Recent Activity
                  //----------------------------------------------------------------
                  const Text(
                    'Recent Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (recentTrip == null) ...[
                            const Icon(
                              Icons.history,
                              size: 48,
                              color: Colors.grey,
                            ),

                            const SizedBox(height: 12),

                            const Text('No recent activity.'),
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Latest booking is ${recentTrip.status.name}.',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        '${recentTrip.pickupAddress} → ${recentTrip.destinationAddress}',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Center(
                    child: Text(
                      'Voltrike Passenger v1.0.0',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PassengerRatingsCard extends StatelessWidget {
  const _PassengerRatingsCard({required this.passengerId, required this.trips});

  final String passengerId;
  final List<Booking> trips;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DriverRating>>(
      stream: DriverRatingRepository().passengerRatings(passengerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: ListTile(
              leading: CircularProgressIndicator(),
              title: Text('Checking trip feedback'),
            ),
          );
        }

        final ratings = snapshot.data ?? const <DriverRating>[];
        final ratedBookingIds = ratings
            .map((rating) => rating.bookingId)
            .toSet();
        final pending =
            trips
                .where(
                  (booking) =>
                      booking.status == BookingStatus.completed &&
                      booking.driverId != null &&
                      !ratedBookingIds.contains(booking.bookingId),
                )
                .toList()
              ..sort(
                (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
                  a.completedAt ?? a.updatedAt,
                ),
              );
        final latest = ratings.isEmpty ? null : ratings.first;
        Booking? latestTrip;
        if (latest != null) {
          for (final booking in trips) {
            if (booking.bookingId == latest.bookingId) {
              latestTrip = booking;
              break;
            }
          }
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber),
                    SizedBox(width: 8),
                    Text(
                      'Trip feedback',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  pending.isEmpty
                      ? 'All completed trips have been reviewed.'
                      : '${pending.length} completed '
                            '${pending.length == 1 ? 'trip is' : 'trips are'} '
                            'waiting for your rating.',
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push(
                      AppRoutes.rateDriver,
                      extra: pending.first.bookingId,
                    ),
                    icon: const Icon(Icons.star_outline),
                    label: Text('Rate ${pending.first.driverName ?? 'driver'}'),
                  ),
                ],
                if (latest != null) ...[
                  const Divider(height: 28),
                  Text(
                    'Latest submitted rating: ${latest.rating} ★'
                    '${latestTrip?.driverName == null ? '' : ' for ${latestTrip!.driverName}'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (latest.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      latest.comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ] else if (pending.isEmpty) ...[
                  const SizedBox(height: 4),
                  const Text('No ratings submitted yet.'),
                ],
                if (snapshot.hasError) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Saved ratings could not be refreshed. You can still rate '
                    'a completed trip from Trip History.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
