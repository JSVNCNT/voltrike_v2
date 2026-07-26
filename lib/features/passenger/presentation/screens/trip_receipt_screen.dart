import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../controllers/passenger_booking_flow_controller.dart';
import '../../providers/booking_provider.dart';
import '../../providers/booking_session_provider.dart';
import '../../providers/booking_listener_provider.dart';

class TripReceiptScreen extends ConsumerWidget {
  const TripReceiptScreen({
    super.key,
    required this.bookingId,
    this.driverView = false,
    this.completionFlow = false,
  });

  final String bookingId;
  final bool driverView;
  final bool completionFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingListenerProvider(bookingId));

    return bookingAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Trip Receipt')),
        body: Center(child: Text(DomainErrorMapper.message(error))),
      ),
      data: (booking) => booking == null
          ? const Scaffold(body: Center(child: Text('Receipt not found.')))
          : _ReceiptBody(
              booking: booking,
              driverView: driverView,
              completionFlow: completionFlow,
            ),
    );
  }
}

class _ReceiptBody extends ConsumerWidget {
  const _ReceiptBody({
    required this.booking,
    required this.driverView,
    required this.completionFlow,
  });

  final Booking booking;
  final bool driverView;
  final bool completionFlow;

  Future<void> _disputeSettlement(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request settlement review'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What needs review?',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (reason == null || !context.mounted) return;
      await BookingRepository().disputeSettlement(
        bookingId: booking.bookingId,
        reason: reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settlement review requested.')),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedAt = booking.completedAt ?? booking.updatedAt;
    final currentUser = AuthRepository().currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(driverView ? 'Trip Earnings' : 'Trip Receipt'),
      ),
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
                      _ReceiptRow(
                        driverView ? 'Passenger' : 'Driver',
                        driverView
                            ? (booking.passengerName ?? 'VolTrike passenger')
                            : (booking.driverName ?? 'VolTrike driver'),
                      ),
                      const Divider(),
                      _ReceiptRow(
                        'Payment',
                        '${booking.paymentMethod.toUpperCase()} · '
                            '${booking.settlementStatus.replaceAll('_', ' ')}',
                      ),
                      if (booking.receiptNumber != null) ...[
                        const Divider(),
                        _ReceiptRow('Receipt', booking.receiptNumber!),
                      ],
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
                '₱${booking.amountDue.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),
              if (!driverView) ...[
                FutureBuilder<DriverRating?>(
                  future: currentUser == null
                      ? Future.value(null)
                      : DriverRatingRepository().getRatingForBooking(
                          bookingId: booking.bookingId,
                          passengerId: currentUser.uid,
                        ),
                  builder: (context, snapshot) => snapshot.data != null
                      ? ListTile(
                          leading: const Icon(Icons.star, color: Colors.amber),
                          title: Text(
                            'Your driver rating: ${snapshot.data!.rating} ★',
                          ),
                          subtitle: snapshot.data!.comment.isEmpty
                              ? null
                              : Text(snapshot.data!.comment),
                        )
                      : FilledButton.icon(
                          onPressed: booking.driverId == null
                              ? null
                              : () => context.go(
                                  AppRoutes.rateDriver,
                                  extra: booking.bookingId,
                                ),
                          icon: const Icon(Icons.star_outline),
                          label: const Text('Rate driver'),
                        ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: () => _disputeSettlement(context),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  driverView
                      ? 'Request earnings review'
                      : 'Request settlement review',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  if (driverView) {
                    await BookingRepository().acknowledgeDriverReceipt(
                      bookingId: booking.bookingId,
                    );
                    if (!context.mounted) return;
                  }
                  if (!driverView && completionFlow) {
                    ref.read(bookingSessionProvider.notifier).reset();
                    ref.read(bookingProvider.notifier).reset();
                    ref.read(passengerBookingFlowProvider.notifier).clear();
                  }
                  context.go(
                    driverView ? AppRoutes.driverHome : AppRoutes.passengerHome,
                  );
                },
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
