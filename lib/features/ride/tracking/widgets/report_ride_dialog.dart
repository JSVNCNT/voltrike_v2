import 'package:flutter/material.dart';

class ReportRideDialog extends StatefulWidget {
  const ReportRideDialog({super.key, required this.onSubmit});
  final Future<void> Function(String category, String details) onSubmit;
  @override State<ReportRideDialog> createState() => _ReportRideDialogState();
}
class _ReportRideDialogState extends State<ReportRideDialog> {
  final _details = TextEditingController(); String _category = 'Safety concern'; bool _loading = false;
  @override void dispose() { _details.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('Report ride'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField(initialValue: _category, items: const ['Safety concern','Harassment','Incorrect fare','Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _category = v!)), const SizedBox(height: 12), TextField(controller: _details, maxLines: 3, decoration: const InputDecoration(labelText: 'Details', border: OutlineInputBorder()))]), actions: [TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit'))]);

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await widget.onSubmit(_category, _details.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to submit your report. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
