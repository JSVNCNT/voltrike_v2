import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../passenger/providers/passenger_booking_policy_provider.dart';

class RideCancellationResult {
  const RideCancellationResult({required this.reason, this.comment});

  final String reason;
  final String? comment;
}

/// Shared cancellation confirmation for either participant.
class RideCancelDialog extends ConsumerStatefulWidget {
  const RideCancelDialog({super.key, required this.isDriver});

  final bool isDriver;

  @override
  ConsumerState<RideCancelDialog> createState() => _RideCancelDialogState();
}

class _RideCancelDialogState extends ConsumerState<RideCancelDialog> {
  final _commentController = TextEditingController();
  late String _reason = _reasons.first;

  List<String> get _reasons => widget.isDriver
      ? const <String>[
          'Change of plans',
          'Unable to reach the other rider',
          'Safety concern',
          'Other',
        ]
      : const <String>[
          'Change of plans',
          'Booked by mistake',
          'Driver asked me to cancel',
          'Driver is taking too long',
          'Driver is not moving',
          'Safety concern',
          'Other',
        ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.isDriver ? 'trip' : 'booking';
    final policy = widget.isDriver
        ? null
        : ref.watch(passengerBookingPolicyProvider).value;
    final qualifying =
        _reason == 'Change of plans' || _reason == 'Booked by mistake';
    return AlertDialog(
      title: Text('Cancel $actor?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tell us why you are cancelling.'),
            if (!widget.isDriver) ...[
              const SizedBox(height: 12),
              Text(
                qualifying
                    ? policy == null
                          ? 'After a driver accepts, this reason counts toward the limit of three qualifying cancellations within 24 hours. Reaching the limit restricts new bookings for 24 hours.'
                          : 'This will be qualifying cancellation ${policy.strikes.length + 1} in 24 hours. '
                                '${policy.strikes.length >= 2 ? 'New bookings will be restricted for 24 hours.' : 'Three qualifying cancellations restrict new bookings for 24 hours.'}'
                    : 'Safety and driver-related reasons are reviewed and do not automatically add a cancellation strike.',
              ),
            ],
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value!),
              child: Column(
                children: _reasons
                    .map(
                      (reason) => RadioListTile<String>(
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        title: Text(reason),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_reason == 'Other')
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Please specify',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep ride'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(
            RideCancellationResult(
              reason: _reason,
              comment: _commentController.text.trim().isEmpty
                  ? null
                  : _commentController.text.trim(),
            ),
          ),
          child: const Text('Cancel ride'),
        ),
      ],
    );
  }
}
