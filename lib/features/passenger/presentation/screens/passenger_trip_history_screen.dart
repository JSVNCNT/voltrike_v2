import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';

/// ===========================================================================
/// Passenger Trip History
///
/// Displays all bookings created by the current passenger.
///
/// Future:
/// • View Trip Details
/// • View Rating
/// • Ride Again
/// ===========================================================================
class PassengerTripHistoryScreen
    extends ConsumerWidget {
  const PassengerTripHistoryScreen({
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
            'Not signed in.',
          ),
        ),
      );
    }

    final bookings =
        BookingRepository()
            .bookingsForPassenger(
          user.uid,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trip History',
        ),
      ),
      body: StreamBuilder<
          List<Booking>>(
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

          final trips =
              snapshot.data ?? [];

          if (trips.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 80,
                    color: Colors.grey,
                  ),

                  SizedBox(
                    height: 16,
                  ),

                  Text(
                    'No trips yet.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  SizedBox(
                    height: 8,
                  ),

                  Text(
                    'Your completed rides will appear here.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color:
                          Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          trips.sort(
            (a, b) => b.createdAt
                .compareTo(
              a.createdAt,
            ),
          );

          return ListView.builder(
            padding:
                const EdgeInsets.all(
              16,
            ),
            itemCount:
                trips.length,
            itemBuilder: (
              context,
              index,
            ) {
              final booking =
                  trips[index];
                                return Card(
                margin:
                    const EdgeInsets.only(
                  bottom: 16,
                ),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                  onTap: () {
                    //======================================================
                    // Future:
                    //
                    // Navigate to Trip Details Screen
                    //======================================================
                  },
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
                        //----------------------------------------------------------------
                        // Status
                        //----------------------------------------------------------------

                        Row(
                          children: [
                            Icon(
                              Icons.route,
                              color:
                                  booking.status ==
                                          BookingStatus
                                              .completed
                                      ? Colors.green
                                      : Colors.orange,
                            ),

                            const SizedBox(
                              width: 8,
                            ),

                            Expanded(
                              child: Text(
                                booking.status.name,
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),

                            Text(
                              booking.createdAt
                                  .toLocal()
                                  .toString()
                                  .split(
                                    '.',
                                  )
                                  .first,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        const Divider(
                          height: 24,
                        ),

                        //----------------------------------------------------------------
                        // Pickup
                        //----------------------------------------------------------------

                        ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              const Icon(
                            Icons
                                .my_location,
                            color:
                                Colors.green,
                          ),
                          title:
                              const Text(
                            'Pickup',
                          ),
                          subtitle:
                              Text(
                            booking
                                .pickupAddress,
                          ),
                        ),

                        //----------------------------------------------------------------
                        // Destination
                        //----------------------------------------------------------------

                        ListTile(
                          contentPadding:
                              EdgeInsets.zero,
                          leading:
                              const Icon(
                            Icons
                                .location_on,
                            color:
                                Colors.red,
                          ),
                          title:
                              const Text(
                            'Destination',
                          ),
                          subtitle:
                              Text(
                            booking
                                .destinationAddress,
                          ),
                        ),

                        const SizedBox(
                          height: 12,
                        ),

                        //----------------------------------------------------------------
                        // Fare
                        //----------------------------------------------------------------

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .spaceBetween,
                          children: [
                            const Text(
                              'Estimated Fare',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                              ),
                            ),
                            Text(
                              '₱${booking.estimatedFare.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize: 18,
                                color:
                                    Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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