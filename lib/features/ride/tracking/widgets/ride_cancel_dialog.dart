import 'package:flutter/material.dart';

class RideCancellationResult {
  const RideCancellationResult({
    required this.reason,
    this.comment,
  });

  final String reason;
  final String? comment;
}

/// Shared cancellation confirmation for either participant.
class RideCancelDialog extends StatefulWidget {
  const RideCancelDialog({
    super.key,
    required this.isDriver,
  });

  final bool isDriver;

  @override
  State<RideCancelDialog> createState() => _RideCancelDialogState();
}

class _RideCancelDialogState extends State<RideCancelDialog> {
  final _commentController = TextEditingController();
  late String _reason = _reasons.first;

  static const _reasons = <String>[
    'Change of plans',
    'Unable to reach the other rider',
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
    return AlertDialog(
      title: Text('Cancel $actor?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tell us why you are cancelling.'),
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
