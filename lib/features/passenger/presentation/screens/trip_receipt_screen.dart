import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../driver/providers/driver_current_booking_provider.dart';
import '../../../driver/providers/driver_incoming_booking_provider.dart';
import '../../../driver/providers/driver_trip_provider.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../controllers/passenger_booking_flow_controller.dart';
import '../../providers/booking_listener_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/booking_session_provider.dart';

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
          title: Text(
            driverView
                ? 'Request earnings review'
                : 'Request settlement review',
          ),
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
    final colors = Theme.of(context).colorScheme;
    final participantName = driverView
        ? (booking.passengerName ?? 'VolTrike passenger')
        : (booking.driverName ?? 'VolTrike driver');
    final paymentStatus = booking.settlementStatus
        .replaceAll('_', ' ')
        .toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(driverView ? 'Trip Earnings' : 'Trip Receipt'),
      ),
      bottomNavigationBar: _ReceiptHomeButton(
        bookingId: booking.bookingId,
        driverView: driverView,
        completionFlow: completionFlow,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: colors.onPrimary,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Trip completed',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      driverView
                          ? 'Your cash earnings have been settled.'
                          : 'Your trip and cash payment are complete.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '\u20B1${booking.amountDue.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.primary,
                          ),
                    ),
                    Text(
                      driverView ? 'Trip earnings' : 'Amount paid',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Trip details',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      _ReceiptRow(
                        icon: Icons.trip_origin_rounded,
                        label: 'Pickup',
                        value: booking.pickupAddress,
                      ),
                      const Divider(),
                      _ReceiptRow(
                        icon: Icons.location_on_rounded,
                        label: 'Destination',
                        value: booking.destinationAddress,
                      ),
                      const Divider(),
                      _ReceiptRow(
                        icon: Icons.route_rounded,
                        label: 'Distance',
                        value:
                            '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                      ),
                      const Divider(),
                      _ReceiptRow(
                        icon: Icons.person_outline_rounded,
                        label: driverView ? 'Passenger' : 'Driver',
                        value: participantName,
                      ),
                      const Divider(),
                      _ReceiptRow(
                        icon: Icons.payments_outlined,
                        label: 'Payment',
                        value:
                            '${booking.paymentMethod.toUpperCase()} \u2022 $paymentStatus',
                      ),
                      if (booking.receiptNumber != null) ...[
                        const Divider(),
                        _ReceiptRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'Receipt',
                          value: booking.receiptNumber!,
                        ),
                      ],
                      const Divider(),
                      _ReceiptRow(
                        icon: Icons.schedule_rounded,
                        label: 'Completed',
                        value: completedAt
                            .toLocal()
                            .toString()
                            .split('.')
                            .first,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Need help?',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: driverView || booking.driverId != null
                    ? () => showRideReportDialog(
                        context: context,
                        booking: booking,
                        reporterIsDriver: driverView,
                      )
                    : null,
                icon: const Icon(Icons.report_problem_outlined),
                label: Text(driverView ? 'Report passenger' : 'Report driver'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _disputeSettlement(context),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  driverView
                      ? 'Request earnings review'
                      : 'Request settlement review',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptHomeButton extends ConsumerStatefulWidget {
  const _ReceiptHomeButton({
    required this.bookingId,
    required this.driverView,
    required this.completionFlow,
  });

  final String bookingId;
  final bool driverView;
  final bool completionFlow;

  @override
  ConsumerState<_ReceiptHomeButton> createState() => _ReceiptHomeButtonState();
}

class _ReceiptHomeButtonState extends ConsumerState<_ReceiptHomeButton> {
  bool _isReturningHome = false;

  Future<void> _returnHome() async {
    if (_isReturningHome) return;
    setState(() => _isReturningHome = true);

    try {
      if (widget.driverView) {
        await BookingRepository().acknowledgeDriverReceipt(
          bookingId: widget.bookingId,
        );
      }
      if (!mounted) return;

      if (widget.driverView) {
        ref.read(driverCurrentBookingProvider.notifier).clearBooking();
        ref.read(driverIncomingBookingProvider.notifier).clearBooking();
        ref.read(driverTripProvider.notifier).reset();
      } else if (widget.completionFlow) {
        ref.read(bookingSessionProvider.notifier).reset();
        ref.read(bookingProvider.notifier).reset();
        ref.read(passengerBookingFlowProvider.notifier).clear();
      }
      context.go(
        widget.driverView ? AppRoutes.driverHome : AppRoutes.passengerHome,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not return home: ${DomainErrorMapper.message(error)}',
          ),
        ),
      );
      setState(() => _isReturningHome = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: FilledButton.icon(
        onPressed: _isReturningHome ? null : _returnHome,
        icon: _isReturningHome
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.home_outlined),
        label: Text(_isReturningHome ? 'Returning home...' : 'Back to Home'),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
