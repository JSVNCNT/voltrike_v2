import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/booking.dart';

/// Shared expandable representation of a completed or cancelled ride.
class ExpandableTripCard extends StatefulWidget {
  const ExpandableTripCard({
    super.key,
    required this.booking,
    required this.otherPartyLabel,
    this.onReceipt,
    this.onRate,
    this.onReport,
  });

  final Booking booking;
  final String otherPartyLabel;
  final VoidCallback? onReceipt;
  final VoidCallback? onRate;
  final VoidCallback? onReport;

  @override
  State<ExpandableTripCard> createState() => _ExpandableTripCardState();
}

class _ExpandableTripCardState extends State<ExpandableTripCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final completed = booking.status == BookingStatus.completed;
    return Card(
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(completed ? Icons.check_circle : Icons.cancel,
                    color: completed ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.otherPartyLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(DateFormat('MMM d, yyyy').format(booking.completedAt ?? booking.updatedAt)),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ]),
              const SizedBox(height: 10),
              Text(booking.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
              const Icon(Icons.arrow_downward, size: 16),
              Text(booking.destinationAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (_expanded) ...[
                const Divider(height: 24),
                Text('Fare: PHP ${booking.estimatedFare.toStringAsFixed(2)}'),
                Text('Distance: ${(booking.distanceMeters / 1000).toStringAsFixed(1)} km'),
                Text('Reference: ${booking.bookingId}'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (widget.onReceipt != null) OutlinedButton(onPressed: widget.onReceipt, child: const Text('Receipt')),
                  if (completed && widget.onRate != null) FilledButton(onPressed: widget.onRate, child: const Text('Rate')),
                  if (widget.onReport != null) OutlinedButton(onPressed: widget.onReport, child: const Text('Report')),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
