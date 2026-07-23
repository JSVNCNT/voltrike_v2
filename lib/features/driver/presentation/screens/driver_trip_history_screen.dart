import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/empty_state.dart';
import '../../controllers/driver_trip_history_controller.dart';

class DriverTripHistoryScreen extends ConsumerWidget {
  const DriverTripHistoryScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(
      driverTripHistoryProvider,
    );

    return Scaffold(
      appBar: const AppAppBar(
        title: 'Trip History',
      ),
      body: trips.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, _) => Center(
          child: Text(
            error.toString(),
          ),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const EmptyState(
              title: 'No Trips Yet',
              message:
                  'Your completed trips will appear here.',
              icon: Icons.receipt_long_outlined,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final booking = bookings[index];

              final completedDate =
                  booking.completedAt ??
                      booking.updatedAt;

              return Card(
                elevation: 2,
                child: Padding(
                  padding:
                      const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat(
                                'MMM dd, yyyy • hh:mm a',
                              ).format(
                                completedDate,
                              ),
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      ListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        leading: const Icon(
                          Icons.my_location,
                          color: Colors.green,
                        ),
                        title: const Text(
                          'Pickup',
                        ),
                        subtitle: Text(
                          booking.pickupAddress,
                        ),
                      ),

                      ListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        leading: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Destination',
                        ),
                        subtitle: Text(
                          booking.destinationAddress,
                        ),
                      ),

                      const Divider(),

                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          const Text(
                            'Fare',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₱${booking.estimatedFare.toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              color:
                                  Colors.green,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
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