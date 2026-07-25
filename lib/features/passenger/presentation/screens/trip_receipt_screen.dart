import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../providers/booking_listener_provider.dart';
import 'rating_screen.dart';

class TripReceiptScreen extends ConsumerWidget {
  const TripReceiptScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingListenerProvider(bookingId));

    return bookingAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Trip Receipt')),
        body: Center(child: Text(error.toString())),
      ),
      data: (booking) => booking == null
          ? const Scaffold(body: Center(child: Text('Receipt not found.')))
          : _ReceiptBody(booking: booking),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final completedAt = booking.completedAt ?? booking.updatedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Receipt')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Trip completed',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _ReceiptRow('Pickup', booking.pickupAddress),
                      const Divider(),
                      _ReceiptRow('Destination', booking.destinationAddress),
                      const Divider(),
                      _ReceiptRow(
                        'Distance',
                        '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                      ),
                      const Divider(),
                      _ReceiptRow('Driver', booking.driverName ?? 'VolTrike driver'),
                      const Divider(),
                      _ReceiptRow(
                        'Completed',
                        completedAt.toLocal().toString().split('.').first,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '₱${booking.estimatedFare.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: booking.driverId == null
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => RatingScreen(bookingId: booking.bookingId),
                          ),
                        ),
                icon: const Icon(Icons.star_outline),
                label: const Text('Rate driver'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Return home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    );
  }
}
