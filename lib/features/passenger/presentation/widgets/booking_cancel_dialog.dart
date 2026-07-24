import 'package:flutter/material.dart';

/// ===========================================================================
/// Booking Cancellation Result
///
/// Represents the result of a booking cancellation.
/// ===========================================================================
class BookingCancellationResult {
  const BookingCancellationResult({
    required this.reason,
    this.comment,
  });

  final String reason;
  final String? comment;
}

/// ===========================================================================
/// Booking Cancel Dialog
/// ===========================================================================
class BookingCancelDialog extends StatefulWidget {
  const BookingCancelDialog({
    super.key,
  });

  @override
  State<BookingCancelDialog> createState() =>
      _BookingCancelDialogState();
}

class _BookingCancelDialogState
    extends State<BookingCancelDialog> {
  static const List<String> _reasons = [
    'Driver asked me to cancel',
    'Driver is taking too long',
    'Driver is not moving',
    'Change of plans',
    'Booked by mistake',
    'Other',
  ];

  final TextEditingController _commentController =
      TextEditingController();

  String _selectedReason = _reasons.first;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    final comment = _selectedReason == 'Other'
        ? _commentController.text.trim()
        : _commentController.text.trim();

    Navigator.of(context).pop(
      BookingCancellationResult(
        reason: _selectedReason,
        comment: comment.isEmpty ? null : comment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel Booking'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Why are you cancelling?',
            ),

            const SizedBox(height: 16),

            RadioGroup<String>(
              groupValue: _selectedReason,
              onChanged: (String? value) {
                if (value == null) return;

                setState(() {
                  _selectedReason = value;
                });
              },
              child: Column(
                children: _reasons
                    .map(
                      (reason) =>
                          RadioListTile<String>(
                        value: reason,
                        title: Text(reason),
                        contentPadding:
                            EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
            ),

            if (_selectedReason == 'Other') ...[
              const SizedBox(height: 16),
              TextField(
                controller:
                    _commentController,
                maxLines: 3,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Please specify',
                  hintText:
                      'Enter your reason',
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Keep Booking',
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(
            'Cancel Booking',
          ),
        ),
      ],
    );
  }
}