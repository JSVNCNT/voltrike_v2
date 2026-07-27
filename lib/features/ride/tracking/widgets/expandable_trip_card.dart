import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';

/// Shared expandable representation of a completed or cancelled ride.
class ExpandableTripCard extends StatefulWidget {
  const ExpandableTripCard({
    super.key,
    required this.booking,
    required this.otherPartyLabel,
    this.otherPartyPhotoUrl,
    this.onReceipt,
    this.onRate,
    this.onReport,
    this.submittedRating,
  });

  final Booking booking;
  final String otherPartyLabel;
  final String? otherPartyPhotoUrl;
  final VoidCallback? onReceipt;
  final VoidCallback? onRate;
  final VoidCallback? onReport;
  final int? submittedRating;

  @override
  State<ExpandableTripCard> createState() => _ExpandableTripCardState();
}

class _ExpandableTripCardState extends State<ExpandableTripCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final completed = booking.status == BookingStatus.completed;
    final cancellationLabel = switch (booking.cancellationCode) {
      'passenger_no_show' => 'Passenger no-show',
      'cancelled_by_passenger' => 'Cancelled by Passenger',
      'cancelled_by_driver' => 'Cancelled by Driver',
      _ => 'Cancelled',
    };
    return Card(
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage:
                        widget.otherPartyPhotoUrl?.isNotEmpty == true
                        ? NetworkImage(widget.otherPartyPhotoUrl!)
                        : null,
                    child: widget.otherPartyPhotoUrl?.isNotEmpty == true
                        ? null
                        : const Icon(Icons.person_outline),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.otherPartyLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    DateFormat(
                      'MMM d, yyyy',
                    ).format(BookingStateMachine.terminalDate(booking)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                completed ? 'Completed' : cancellationLabel,
                style: TextStyle(
                  color: completed ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (completed && widget.submittedRating != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Your rating: ${widget.submittedRating} ★',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                booking.pickupAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Icon(Icons.arrow_downward, size: 16),
              Text(
                booking.destinationAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_expanded) ...[
                const Divider(height: 24),
                Text('Fare: PHP ${booking.amountDue.toStringAsFixed(2)}'),
                Text(
                  'Distance: ${(booking.distanceMeters / 1000).toStringAsFixed(1)} km',
                ),
                Text('Reference: ${booking.bookingId}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onReceipt != null)
                      OutlinedButton(
                        onPressed: widget.onReceipt,
                        child: const Text('Receipt'),
                      ),
                    if (completed && widget.onRate != null)
                      FilledButton(
                        onPressed: widget.onRate,
                        child: const Text('Rate'),
                      ),
                    if (widget.onReport != null)
                      OutlinedButton(
                        onPressed: widget.onReport,
                        child: const Text('Report'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
