import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../data/repositories/driver_repository.dart';

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
class DriverDashboardScreen
    extends ConsumerWidget {
  const DriverDashboardScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final auth =
        AuthRepository();

    final user =
        auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Driver not signed in.',
          ),
        ),
      );
    }

    final driverRepository =
        DriverRepository();

    final bookingRepository =
        BookingRepository();

    final ratingRepository =
        DriverRatingRepository();

    final driverStream =
        driverRepository.driverStream(
      user.uid,
    );

    final bookingStream =
        bookingRepository
            .bookingsForDriver(
          user.uid,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Driver Dashboard',
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await auth.signOut();

              if (context.mounted) {
                Navigator.popUntil(
                  context,
                  (route) =>
                      route.isFirst,
                );
              }
            },
            icon: const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: driverStream,
                builder: (
          context,
          driverSnapshot,
        ) {
          if (driverSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          if (driverSnapshot.hasError) {
            return Center(
              child: Text(
                driverSnapshot.error
                    .toString(),
              ),
            );
          }

          final driver =
              driverSnapshot.data;

          if (driver == null) {
            return const Center(
              child: Text(
                'Driver profile not found.',
              ),
            );
          }

          return FutureBuilder<double>(
            future:
                ratingRepository
                    .getAverageRating(
              driver.uid,
            ),
            builder: (
              context,
              ratingSnapshot,
            ) {
              final averageRating =
                  ratingSnapshot.data ??
                      0;

              return StreamBuilder<
                  List<Booking>>(
                stream:
                    bookingStream,
                builder: (
                  context,
                  bookingSnapshot,
                ) {
                  if (bookingSnapshot
                          .connectionState ==
                      ConnectionState
                          .waiting) {
                    return const Center(
                      child:
                          CircularProgressIndicator(),
                    );
                  }

                  final bookings =
                      bookingSnapshot
                              .data ??
                          [];

                  final completedTrips =
                      bookings
                          .where(
                            (booking) =>
                                booking.status ==
                                BookingStatus
                                    .completed,
                          )
                          .length;

                  final currentBooking =
                      bookings
                          .where(
                            (booking) =>
                                booking.status !=
                                    BookingStatus
                                        .completed &&
                                booking.status !=
                                    BookingStatus
                                        .cancelled,
                          )
                          .cast<Booking?>()
                          .firstWhere(
                            (_) => true,
                            orElse:
                                () => null,
                          );

                  final totalEarnings =
                      bookings.fold<double>(
                    0,
                    (
                      total,
                      booking,
                    ) {
                      if (booking.status ==
                          BookingStatus
                              .completed) {
                        return total +
                            booking
                                .estimatedFare;
                      }

                      return total;
                    },
                  );

                  return SafeArea(
                    child:
                        SingleChildScrollView(
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
                                    style:
                                        TextStyle(
                                      color:
                                          Colors
                                              .grey,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 6,
                                  ),

                                  Text(
                                    driver.uid,
                                    style:
                                        const TextStyle(
                                      fontSize:
                                          22,
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 16,
                                  ),

                                  Row(
                                    children: [
                                      Icon(
                                        driver.isOnline
                                            ? Icons
                                                .circle
                                            : Icons
                                                .circle_outlined,
                                        color:
                                            driver.isOnline
                                                ? Colors
                                                    .green
                                                : Colors
                                                    .red,
                                        size: 14,
                                      ),

                                      const SizedBox(
                                        width: 8,
                                      ),

                                      Text(
                                        driver.isOnline
                                            ? 'ONLINE'
                                            : 'OFFLINE',
                                        style:
                                            TextStyle(
                                          color:
                                              driver.isOnline
                                                  ? Colors
                                                      .green
                                                  : Colors
                                                      .red,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          //----------------------------------------------------------------
                          // Statistics
                          //----------------------------------------------------------------

                          Row(
                            children: [
                              Expanded(
                                child: Card(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(
                                      16,
                                    ),
                                    child:
                                        Column(
                                      children: [
                                        const Icon(
                                          Icons
                                              .star,
                                          color:
                                              Colors
                                                  .amber,
                                        ),

                                        const SizedBox(
                                          height:
                                              8,
                                        ),

                                        Text(
                                          averageRating
                                              .toStringAsFixed(
                                            1,
                                          ),
                                          style:
                                              const TextStyle(
                                            fontSize:
                                                22,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        const SizedBox(
                                          height:
                                              4,
                                        ),

                                        const Text(
                                          'Rating',
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
                                    child:
                                        Column(
                                      children: [
                                        const Icon(
                                          Icons
                                              .check_circle,
                                          color:
                                              Colors
                                                  .green,
                                        ),

                                        const SizedBox(
                                          height:
                                              8,
                                        ),

                                        Text(
                                          completedTrips
                                              .toString(),
                                          style:
                                              const TextStyle(
                                            fontSize:
                                                22,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        const SizedBox(
                                          height:
                                              4,
                                        ),

                                        const Text(
                                          'Trips',
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

                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(
                                20,
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons
                                        .payments,
                                    color:
                                        Colors
                                            .green,
                                    size: 36,
                                  ),

                                  const SizedBox(
                                    height: 12,
                                  ),

                                  const Text(
                                    'Total Earnings',
                                    style:
                                        TextStyle(
                                      color:
                                          Colors
                                              .grey,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 8,
                                  ),

                                  Text(
                                    '₱${totalEarnings.toStringAsFixed(2)}',
                                    style:
                                        const TextStyle(
                                      fontSize:
                                          28,
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
                            ),
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          //----------------------------------------------------------------
                          // Current Booking
                          //----------------------------------------------------------------

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
                                  const Text(
                                    'Current Booking',
                                    style:
                                        TextStyle(
                                      fontSize:
                                          18,
                                      fontWeight:
                                          FontWeight
                                              .bold,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 12,
                                  ),

                                  if (currentBooking ==
                                      null)
                                    const Text(
                                      'No active booking.',
                                    )
                                  else ...[
                                    ListTile(
                                      contentPadding:
                                          EdgeInsets.zero,
                                      leading:
                                          const Icon(
                                        Icons
                                            .my_location,
                                      ),
                                      title:
                                          const Text(
                                        'Pickup',
                                      ),
                                      subtitle:
                                          Text(
                                        currentBooking
                                            .pickupAddress,
                                      ),
                                    ),

                                    ListTile(
                                      contentPadding:
                                          EdgeInsets.zero,
                                      leading:
                                          const Icon(
                                        Icons
                                            .location_on,
                                      ),
                                      title:
                                          const Text(
                                        'Destination',
                                      ),
                                      subtitle:
                                          Text(
                                        currentBooking
                                            .destinationAddress,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(
                            height: 20,
                          ),
                                                    //----------------------------------------------------------------
                          // Quick Actions
                          //----------------------------------------------------------------

                          const Text(
                            'Quick Actions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics:
                                const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.35,
                            children: [
                              Card(
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    12,
                                  ),
                                  onTap: () {
                              context.push(AppRoutes.driverTripHistory);
                                  },
                                  child: const Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.history,
                                        size: 36,
                                      ),
                                      SizedBox(
                                        height: 12,
                                      ),
                                      Text(
                                        'Trip History',
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              Card(
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    12,
                                  ),
                                  onTap: () {
                           context.push(AppRoutes.driverProfile);
                            },
                                  child: const Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: 36,
                                      ),
                                      SizedBox(
                                        height: 12,
                                      ),
                                      Text(
                                        'Profile',
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              Card(
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    12,
                                  ),
                                  onTap: () {
                         context.push(
                        AppRoutes.driverEarnings,
                extra: driver.uid,
              );
                    },
                                  child: const Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet,
                                        size: 36,
                                      ),
                                      SizedBox(
                                        height: 12,
                                      ),
                                      Text(
                                        'Earnings',
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              Card(
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    12,
                                  ),
                                  onTap: () async {
                              if (driver.isOnline) {
                         await driverRepository.goOffline(
                    driver.uid,
                     );
              } else {
             await driverRepository.goOnline(
             driver.uid,
             );
          }
        },
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        driver.isOnline
                                            ? Icons
                                                .toggle_on
                                            : Icons
                                                .toggle_off,
                                        size: 40,
                                        color:
                                            driver.isOnline
                                                ? Colors.green
                                                : Colors.grey,
                                      ),
                                      const SizedBox(
                                        height: 12,
                                      ),
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

                          const SizedBox(
                            height: 24,
                          ),
                                                  ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}