import 'package:flutter/material.dart';

class ReportRideDialog extends StatefulWidget {
  const ReportRideDialog({
    super.key,
    required this.onSubmit,
    this.reporterIsDriver = false,
  });
  final Future<void> Function(String category, String details) onSubmit;
  final bool reporterIsDriver;
  @override State<ReportRideDialog> createState() => _ReportRideDialogState();
}
class _ReportRideDialogState extends State<ReportRideDialog> {
  final _details = TextEditingController(); String _category = ''; bool _loading = false;
  List<String> get _categories => widget.reporterIsDriver
      ? const ['Passenger safety', 'Passenger behavior', 'Pickup issue', 'Fare dispute', 'Other']
      : const ['Driver safety', 'Driver behavior', 'Vehicle concern', 'Fare dispute', 'Other'];
  @override void initState() { super.initState(); _category = _categories.first; }
  @override void dispose() { _details.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('Report ride'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField(initialValue: _category, items: _categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _category = v!)), const SizedBox(height: 12), TextField(controller: _details, maxLines: 3, decoration: const InputDecoration(labelText: 'What happened?', hintText: 'Add details for TODA review', border: OutlineInputBorder()))]), actions: [TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit'))]);

  Future<void> _submit() async {
    if (_details.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a short description of the concern.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.onSubmit(_category, _details.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
