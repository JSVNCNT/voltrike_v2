import 'package:flutter/material.dart';

import '../../../../app/app_config.dart';
import '../../../../core/services/system_diagnostics_service.dart';

class SystemDiagnosticsTile extends StatefulWidget {
  const SystemDiagnosticsTile({super.key});

  @override
  State<SystemDiagnosticsTile> createState() => _SystemDiagnosticsTileState();
}

class _SystemDiagnosticsTileState extends State<SystemDiagnosticsTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await SystemDiagnosticsService().check();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            result.compatible
                ? 'Defense environment ready'
                : 'Version mismatch',
          ),
          content: Text(
            'Client ${AppConfig.version} / protocol '
            '${AppConfig.clientProtocolVersion}\n'
            'Functions protocol ${result.functionsVersion}\n'
            'Booking schema ${result.bookingSchemaVersion}\n'
            'Region ${result.region}\n'
            'Project ${result.projectId}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.health_and_safety_outlined),
      title: const Text('System diagnostics'),
      subtitle: const Text('Check backend and schema compatibility'),
      trailing: _checking
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _checking ? null : _check,
    );
  }
}
