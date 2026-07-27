import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';

/// ===========================================================================
/// Driver Dashboard
///
/// Main screen for authenticated drivers.
///
/// Displays:
/// • Online / Offline status
/// • Current booking
/// • Today's earnings
/// • Total earnings
/// • Average rating
/// • Completed trips
/// • Quick actions
/// ===========================================================================
class DriverDashboardScreen extends ConsumerWidget {
  const DriverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = AuthRepository();

    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Driver not signed in.')));
    }

    final driverRepository = DriverRepository();

    final bookingRepository = BookingRepository();

    final driverStream = driverRepository.driverStream(user.uid);

    final bookingStream = bookingRepository.bookingsForDriver(user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(
            onPressed: () async {
              await auth.signOut();

              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: driverStream,
        builder: (context, driverSnapshot) {
          if (driverSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (driverSnapshot.hasError) {
            return Center(child: Text(driverSnapshot.error.toString()));
          }

          final driver = driverSnapshot.data;

          if (driver == null) {
            return const Center(child: Text('Driver profile not found.'));
          }

          final averageRating = driver.rating;
          return StreamBuilder<List<Booking>>(
            stream: bookingStream,
            builder: (context, bookingSnapshot) {
              if (bookingSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final bookings = bookingSnapshot.data ?? [];

              final completedTrips = bookings
                  .where((booking) => booking.status == BookingStatus.completed)
                  .length;

              final cancelledTrips = bookings
                  .where((booking) => booking.status == BookingStatus.cancelled)
                  .length;

              final currentBooking = bookings
                  .where(
                    (booking) =>
                        booking.status != BookingStatus.completed &&
                        booking.status != BookingStatus.cancelled,
                  )
                  .cast<Booking?>()
                  .firstWhere((_) => true, orElse: () => null);

              final totalEarnings = bookings.fold<double>(0, (total, booking) {
                if (booking.status == BookingStatus.completed) {
                  return total + booking.amountDue;
                }

                return total;
              });

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

                              const SizedBox(height: 6),

                              FutureBuilder(
                                future: UserRepository().getUser(user.uid),
                                builder: (context, snapshot) => Text(
                                  snapshot.data?.fullName ??
                                      user.displayName ??
                                      'Driver',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  Icon(
                                    driver.isOnline
                                        ? Icons.circle
                                        : Icons.circle_outlined,
                                    color: driver.isOnline
                                        ? Colors.green
                                        : Colors.red,
                                    size: 14,
                                  ),

                                  const SizedBox(width: 8),

                                  Text(
                                    driver.isOnline ? 'ONLINE' : 'OFFLINE',
                                    style: TextStyle(
                                      color: driver.isOnline
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      //----------------------------------------------------------------
                      // Statistics
                      //----------------------------------------------------------------
                      Row(
                        children: [
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber),

                                    const SizedBox(height: 8),

                                    Text(
                                      averageRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    const Text('Rating'),
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
                                    ),

                                    const SizedBox(height: 8),

                                    Text(
                                      completedTrips.toString(),
                                      style: const TextStyle(
                                        fontSize: 22,
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    const Icon(Icons.cancel, color: Colors.red),
                                    const SizedBox(height: 8),
                                    Text(
                                      cancelledTrips.toString(),
                                      style: const TextStyle(
                                        fontSize: 22,
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

                      const SizedBox(height: 12),

                      _DriverRatingsCard(
                        driverId: driver.uid,
                        aggregateRating: driver.rating,
                        ratingCount: driver.ratingCount,
                      ),

                      const SizedBox(height: 12),

                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.payments,
                                color: Colors.green,
                                size: 36,
                              ),

                              const SizedBox(height: 12),

                              const Text(
                                'Your Earnings',
                                style: TextStyle(color: Colors.grey),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                '₱${totalEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      //----------------------------------------------------------------
                      // Current Booking
                      //----------------------------------------------------------------
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Booking',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 12),

                              if (currentBooking == null)
                                const Text('No active booking.')
                              else ...[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.my_location),
                                  title: const Text('Pickup'),
                                  subtitle: Text(currentBooking.pickupAddress),
                                ),

                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.location_on),
                                  title: const Text('Destination'),
                                  subtitle: Text(
                                    currentBooking.destinationAddress,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => context.push(
                                          AppRoutes.driverBookingTracking,
                                          extra: currentBooking.bookingId,
                                        ),
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text('Open trip'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => showRideReportDialog(
                                          context: context,
                                          booking: currentBooking,
                                          reporterIsDriver: true,
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

                      const SizedBox(height: 20),

                      //----------------------------------------------------------------
                      // Quick Actions
                      //----------------------------------------------------------------
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.35,
                        children: [
                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                context.push(
                                  AppRoutes.driverEarnings,
                                  extra: driver.uid,
                                );
                              },
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance_wallet, size: 36),
                                  SizedBox(height: 12),
                                  Text('Your Earnings'),
                                ],
                              ),
                            ),
                          ),

                          Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                if (driver.isOnline) {
                                  await driverRepository.goOffline(driver.uid);
                                } else {
                                  await driverRepository.goOnline(driver.uid);
                                }
                              },
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    driver.isOnline
                                        ? Icons.toggle_on
                                        : Icons.toggle_off,
                                    size: 40,
                                    color: driver.isOnline
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    driver.isOnline
                                        ? 'Go Offline'
                                        : 'Go Online',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DriverRatingsCard extends StatelessWidget {
  const _DriverRatingsCard({
    required this.driverId,
    required this.aggregateRating,
    required this.ratingCount,
  });

  final String driverId;
  final double aggregateRating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DriverRating>>(
      stream: DriverRatingRepository().driverRatings(driverId),
      builder: (context, snapshot) {
        final recent = snapshot.data ?? const <DriverRating>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.reviews, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Passenger feedback',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${aggregateRating.toStringAsFixed(1)} ★ '
                      '· $ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'}',
                    ),
                  ],
                ),
                if (snapshot.connectionState == ConnectionState.waiting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ] else if (snapshot.hasError) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Recent feedback could not be refreshed.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ] else if (recent.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('No passenger feedback yet.'),
                ] else
                  for (final rating in recent.take(3)) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Text(
                          '${rating.rating} ★',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            rating.comment.isEmpty
                                ? 'Passenger left a star rating.'
                                : rating.comment,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
