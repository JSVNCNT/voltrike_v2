import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';

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
  const PassengerDashboardScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final auth = AuthRepository();

    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Passenger not signed in.',
          ),
        ),
      );
    }

    final bookings =
        BookingRepository().bookingsForPassenger(
      user.uid,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dashboard',
        ),
      ),
      body: StreamBuilder<List<Booking>>(
        stream: bookings,
        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error.toString(),
              ),
            );
          }

          final List<Booking> trips =
              snapshot.data ?? <Booking>[];

          Booking? recentTrip;

          if (trips.isNotEmpty) {
            trips.sort(
              (Booking a, Booking b) =>
                  b.createdAt.compareTo(
                a.createdAt,
              ),
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
                totalSpent +=
                    booking.estimatedFare;
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

          final double averageFare =
              completedTrips == 0
                  ? 0
                  : totalSpent /
                      completedTrips;

          return SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .stretch,
                children: [
                  //----------------------------------------------------------------
                  // Welcome Card
                  //----------------------------------------------------------------

                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              color:
                                  Colors.grey,
                            ),
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          Text(
                            user.email ??
                                'Passenger',
                            style:
                                const TextStyle(
                              fontSize: 22,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 20,
                  ),

                                    //----------------------------------------------------------------
                  // Ride Statistics
                  //----------------------------------------------------------------

                  const Text(
                    'Ride Statistics',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.route,
                                  color: Colors.blue,
                                  size: 36,
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                Text(
                                  trips.length
                                      .toString(),
                                  style:
                                      const TextStyle(
                                    fontSize: 24,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 4,
                                ),

                                const Text(
                                  'Total Trips',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 36,
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                Text(
                                  completedTrips
                                      .toString(),
                                  style:
                                      const TextStyle(
                                    fontSize: 24,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 4,
                                ),

                                const Text(
                                  'Completed',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  color: Colors.orange,
                                  size: 36,
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                Text(
                                  pendingTrips
                                      .toString(),
                                  style:
                                      const TextStyle(
                                    fontSize: 24,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 4,
                                ),

                                const Text(
                                  'Pending',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Expanded(
                        child: Card(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                  size: 36,
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                Text(
                                  cancelledTrips
                                      .toString(),
                                  style:
                                      const TextStyle(
                                    fontSize: 24,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),

                                const SizedBox(
                                  height: 4,
                                ),

                                const Text(
                                  'Cancelled',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  //----------------------------------------------------------------
                  // Spending Summary
                  //----------------------------------------------------------------

                  const Text(
                    'Spending Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        20,
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding:
                                EdgeInsets.zero,
                            leading: const Icon(
                              Icons.payments,
                              color: Colors.green,
                            ),
                            title: const Text(
                              'Total Spent',
                            ),
                            trailing: Text(
                              '₱${totalSpent.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    Colors.green,
                              ),
                            ),
                          ),

                          const Divider(),

                          ListTile(
                            contentPadding:
                                EdgeInsets.zero,
                            leading: const Icon(
                              Icons.bar_chart,
                              color: Colors.blue,
                            ),
                            title: const Text(
                              'Average Fare',
                            ),
                            trailing: Text(
                              '₱${averageFare.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                                    //----------------------------------------------------------------
                  // Recent Trip
                  //----------------------------------------------------------------

                  const Text(
                    'Recent Trip',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  if (recentTrip == null)
                    const Card(
                      child: Padding(
                        padding:
                            EdgeInsets.all(
                          20,
                        ),
                        child: Center(
                          child: Text(
                            'No trips yet.',
                          ),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            ListTile(
                              contentPadding:
                                  EdgeInsets.zero,
                              leading:
                                  const Icon(
                                Icons.my_location,
                                color:
                                    Colors.green,
                              ),
                              title:
                                  const Text(
                                'Pickup',
                              ),
                              subtitle:
                                  Text(
                                recentTrip
                                    .pickupAddress,
                              ),
                            ),

                            ListTile(
                              contentPadding:
                                  EdgeInsets.zero,
                              leading:
                                  const Icon(
                                Icons.location_on,
                                color:
                                    Colors.red,
                              ),
                              title:
                                  const Text(
                                'Destination',
                              ),
                              subtitle:
                                  Text(
                                recentTrip
                                    .destinationAddress,
                              ),
                            ),

                            const Divider(),

                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .spaceBetween,
                              children: [
                                Chip(
                                  label: Text(
                                    recentTrip
                                        .status
                                        .name,
                                  ),
                                ),
                                Text(
                                  '₱${recentTrip.estimatedFare.toStringAsFixed(2)}',
                                  style:
                                      const TextStyle(
                                    fontSize: 18,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    color:
                                        Colors
                                            .green,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(
                              height: 12,
                            ),

                            Row(
                              children: [
                                const Icon(
                                  Icons
                                      .calendar_today,
                                  size: 16,
                                  color:
                                      Colors.grey,
                                ),

                                const SizedBox(
                                  width: 8,
                                ),

                                Text(
                                  recentTrip
                                      .createdAt
                                      .toLocal()
                                      .toString()
                                      .split(
                                        '.',
                                      )
                                      .first,
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors
                                            .grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(
                    height: 24,
                  ),

                                    //----------------------------------------------------------------
                  // Recent Activity
                  //----------------------------------------------------------------

                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Card(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        20,
                      ),
                      child: Column(
                        children: [
                          if (recentTrip == null) ...[
                            const Icon(
                              Icons.history,
                              size: 48,
                              color: Colors.grey,
                            ),

                            const SizedBox(
                              height: 12,
                            ),

                            const Text(
                              'No recent activity.',
                            ),
                          ] else ...[
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color:
                                      Colors.green,
                                ),

                                const SizedBox(
                                  width: 12,
                                ),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'Latest booking is ${recentTrip.status.name}.',
                                        style:
                                            const TextStyle(
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

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

                  const SizedBox(
                    height: 24,
                  ),

                  Center(
                    child: Text(
                      'Voltrike Passenger v1.0.0',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}