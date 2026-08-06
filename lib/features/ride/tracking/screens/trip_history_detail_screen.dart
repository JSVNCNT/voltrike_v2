import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/utils/trip_location_label.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';
import '../widgets/trip_history_card.dart';

class TripHistoryDetailScreen extends StatelessWidget {
  const TripHistoryDetailScreen({
    super.key,
    required this.booking,
    required this.driverView,
    this.submittedRating,
    this.onReceipt,
    this.onRate,
    this.onReport,
  });

  final Booking booking;
  final bool driverView;
  final int? submittedRating;
  final VoidCallback? onReceipt;
  final VoidCallback? onRate;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final completed = booking.status == BookingStatus.completed;
    final terminalDate = BookingStateMachine.terminalDate(booking);
    final counterpartName = driverView
        ? (booking.passengerName ?? 'Passenger')
        : (booking.driverName ?? 'Driver');
    final counterpartPhoto = driverView
        ? booking.passengerPhotoUrl
        : booking.driverPhotoUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      bottomNavigationBar: _DetailActions(
        completed: completed,
        onReceipt: completed ? onReceipt : null,
        onRate: completed ? onRate : null,
        onReport: onReport,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StatusSummary(
            completed: completed,
            label: completed ? 'Trip completed' : cancellationLabelFor(booking),
            terminalDate: terminalDate,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: driverView ? 'Passenger' : 'Driver',
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colors.primaryContainer,
                  foregroundImage: counterpartPhoto?.trim().isNotEmpty == true
                      ? NetworkImage(counterpartPhoto!)
                      : null,
                  child: counterpartPhoto?.trim().isNotEmpty == true
                      ? null
                      : Icon(
                          Icons.person_outline_rounded,
                          color: colors.onPrimaryContainer,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counterpartName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!driverView && completed) ...[
                        const SizedBox(height: 3),
                        Text(
                          [booking.vehicleNumber, booking.plateNumber]
                              .whereType<String>()
                              .where((e) => e.isNotEmpty)
                              .join(' • '),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                if (submittedRating != null) ...[
                  Icon(Icons.star_rounded, color: semantic.rating),
                  Text(
                    '$submittedRating',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Route',
            child: Column(
              children: [
                _InformationRow(
                  icon: Icons.trip_origin_rounded,
                  label: 'Pickup',
                  value: tripLocationLabel(
                    booking.pickupName,
                    booking.pickupAddress,
                  ),
                ),
                const SizedBox(height: 18),
                _InformationRow(
                  icon: Icons.location_on_rounded,
                  label: 'Destination',
                  value: tripLocationLabel(
                    booking.destinationName,
                    booking.destinationAddress,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: completed ? 'Trip summary' : 'Cancellation details',
            child: Column(
              children: [
                if (completed) ...[
                  _SummaryRow(
                    label: driverView ? 'Trip amount' : 'Fare',
                    value: NumberFormat.currency(
                      locale: 'en_PH',
                      symbol: '₱',
                    ).format(booking.amountDue),
                  ),
                  _SummaryRow(
                    label: 'Distance',
                    value:
                        '${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                  ),
                  _SummaryRow(
                    label: 'Payment',
                    value: _titleCase(booking.paymentMethod),
                  ),
                ] else ...[
                  _SummaryRow(
                    label: 'Status',
                    value: cancellationLabelFor(booking),
                  ),
                  if (booking.cancelledBy?.trim().isNotEmpty == true)
                    _SummaryRow(
                      label: 'Cancelled by',
                      value: _titleCase(booking.cancelledBy!),
                    ),
                  if (booking.cancellationCode?.trim().isNotEmpty == true)
                    _SummaryRow(
                      label: 'Reason',
                      value: _readableCode(booking.cancellationCode!),
                    ),
                ],
                _SummaryRow(
                  label: 'Date',
                  value: DateFormat(
                    'MMM d, yyyy • h:mm a',
                  ).format(terminalDate),
                ),
                _SummaryRow(
                  label: 'Reference',
                  value: booking.bookingId,
                  last: true,
                ),
              ],
            ),
          ),
          if (!driverView &&
              (booking.todaName?.isNotEmpty == true ||
                  booking.plateNumber?.isNotEmpty == true)) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Vehicle and TODA',
              child: Column(
                children: [
                  if (booking.todaName?.isNotEmpty == true)
                    _SummaryRow(label: 'TODA', value: booking.todaName!),
                  if (booking.plateNumber?.isNotEmpty == true)
                    _SummaryRow(
                      label: 'Plate number',
                      value: booking.plateNumber!,
                      last: true,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.completed,
    required this.label,
    required this.terminalDate,
  });

  final bool completed;
  final String label;
  final DateTime terminalDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final color = completed ? semantic.success : theme.colorScheme.error;
    final containerColor = completed
        ? semantic.successContainer
        : theme.colorScheme.errorContainer;
    final onContainerColor = completed
        ? semantic.onSuccessContainer
        : theme.colorScheme.onErrorContainer;
    return Semantics(
      label: '$label on ${DateFormat('MMMM d, yyyy').format(terminalDate)}',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Icon(
              completed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: color,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: onContainerColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('MMMM d, yyyy • h:mm a').format(terminalDate),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 3),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.completed,
    this.onReceipt,
    this.onRate,
    this.onReport,
  });

  final bool completed;
  final VoidCallback? onReceipt;
  final VoidCallback? onRate;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    if (onReceipt == null && onRate == null && onReport == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            if (onReport != null)
              OutlinedButton.icon(
                onPressed: onReport,
                icon: const Icon(Icons.assignment_late_outlined),
                label: const Text('Report'),
              ),
            if (completed && onReceipt != null)
              OutlinedButton.icon(
                onPressed: onReceipt,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Receipt'),
              ),
            if (completed && onRate != null)
              FilledButton.icon(
                onPressed: onRate,
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Rate driver'),
              ),
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.trim().isEmpty) return 'Not available';
  final readable = value.trim().replaceAll('_', ' ');
  return readable
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _readableCode(String value) {
  return _titleCase(value.replaceFirst('cancelled_by_', ''));
}
