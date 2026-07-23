import 'package:flutter/material.dart';

import 'destination_search_bar.dart';
import 'fare_card.dart';

/// ===========================================================================
/// Booking Panel
///
/// Displays the ride booking controls.
///
/// Future:
/// • Pickup
/// • Destination
/// • Fare Estimate
/// • Passenger Count
/// • Baggage
/// • Ride Option
/// • Book Ride
/// ===========================================================================
class BookingPanel extends StatelessWidget {
  const BookingPanel({
    super.key,
    this.onDestinationTap,
    this.onBookRide,
  });

  final VoidCallback? onDestinationTap;

  final VoidCallback? onBookRide;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Book Your Ride',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge,
            ),

            const SizedBox(height: 20),

            DestinationSearchBar(
              onTap: onDestinationTap,
            ),

            const SizedBox(height: 20),

            const FareCard(),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBookRide,
                icon: const Icon(
                  Icons.local_taxi,
                ),
                label: const Text(
                  'Book Ride',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}