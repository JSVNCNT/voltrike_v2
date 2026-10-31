import 'package:flutter/material.dart';

import '../../../../core/services/voltrike_api.dart';
import '../../models/passenger_booking_policy.dart';

class BookingPolicyNotice extends StatefulWidget {
  const BookingPolicyNotice({super.key, required this.policy});

  final PassengerBookingPolicy policy;

  @override
  State<BookingPolicyNotice> createState() => _BookingPolicyNoticeState();
}

class _BookingPolicyNoticeState extends State<BookingPolicyNotice> {
  bool _sending = false;

  Future<void> _appeal({bool restriction = false}) async {
    final draft = await showDialog<_AppealDraft>(
      context: context,
      builder: (_) => _AppealDialog(
        restriction: restriction,
        bookingIds: List.of(widget.policy.appealableBookings),
      ),
    );
    if (draft == null || !mounted) return;
    final bookingId = draft.bookingId;
    final explanation = draft.reason;
    setState(() => _sending = true);
    try {
      await VoltrikeApi.instance.operation(
        restriction
            ? 'appealPassengerBookingRestriction'
            : 'appealPassengerCancellation',
        {'bookingId': bookingId, 'reason': explanation},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restriction
                  ? 'Restriction appeal submitted for System Admin review.'
                  : 'Appeal submitted. This cancellation is paused pending review.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.policy.notice.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.policy.notice,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (widget.policy.appealableBookings.isNotEmpty)
              TextButton.icon(
                onPressed: _sending ? null : _appeal,
                icon: const Icon(Icons.support_agent),
                label: Text(_sending ? 'Submitting…' : 'Appeal a cancellation'),
              ),
            if (widget.policy.canAppealRestriction)
              TextButton(
                onPressed: _sending ? null : () => _appeal(restriction: true),
                child: const Text('Appeal booking restriction'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppealDraft {
  const _AppealDraft(this.bookingId, this.reason);
  final String bookingId;
  final String reason;
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog({required this.restriction, required this.bookingIds});
  final bool restriction;
  final List<String> bookingIds;
  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _reason = TextEditingController();
  late String _bookingId = widget.restriction ? '' : widget.bookingIds.last;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.restriction
          ? 'Appeal booking restriction'
          : 'Appeal a cancellation',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.restriction
                ? 'System Admin will review your explanation. This restriction remains in effect during review.'
                : 'The disputed cancellation will stop counting while System Admin reviews it. Each cancellation can be appealed once.',
          ),
          if (!widget.restriction)
            DropdownButtonFormField<String>(
              initialValue: _bookingId,
              isExpanded: true,
              items: [
                for (final id in widget.bookingIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text('Booking $id', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _bookingId = id!),
            ),
          TextField(
            controller: _reason,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              helperText: 'At least 10 characters',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().length < 10
            ? null
            : () => Navigator.pop(
                context,
                _AppealDraft(_bookingId, _reason.text.trim()),
              ),
        child: const Text('Submit appeal'),
      ),
    ],
  );
}
