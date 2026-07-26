import 'package:flutter/material.dart';

/// ===========================================================================
/// Booking Request Card
///
/// Displays an incoming passenger booking.
///
/// Used in:
/// • DriverHomeScreen
/// • DriverBottomSheet
/// ===========================================================================
class BookingRequestCard extends StatelessWidget {
  const BookingRequestCard({
    super.key,
    required this.passengerName,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedFare,
    required this.distance,
    this.passengerPhotoUrl,
    this.onAccept,
    this.onDecline,
  });

  final String passengerName;
  final String pickupAddress;
  final String destinationAddress;
  final String estimatedFare;
  final String distance;
  final String? passengerPhotoUrl;

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: passengerPhotoUrl?.trim().isNotEmpty == true
                      ? NetworkImage(passengerPhotoUrl!)
                      : null,
                  child: passengerPhotoUrl?.trim().isNotEmpty == true
                      ? null
                      : const Icon(Icons.person),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    passengerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            const Text('Pickup', style: TextStyle(fontWeight: FontWeight.bold)),

            Text(pickupAddress),

            const SizedBox(height: 12),

            const Text(
              'Destination',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            Text(destinationAddress),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Text(
                    estimatedFare,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: Text(distance, textAlign: TextAlign.end)),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    child: const Text('Decline'),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
