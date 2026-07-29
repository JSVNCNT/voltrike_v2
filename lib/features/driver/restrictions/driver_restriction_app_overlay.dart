import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/routes.dart';
import '../../../core/theme/app_semantic_colors.dart';
import 'driver_restriction_monitor.dart';
import 'driver_restriction_monitor_provider.dart';

class DriverRestrictionAppOverlay extends ConsumerWidget {
  const DriverRestrictionAppOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(driverRestrictionMonitorProvider);
    return Stack(
      children: [
        child,
        if (monitor.visible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _DriverRestrictionBanner(state: monitor),
            ),
          ),
      ],
    );
  }
}

class _DriverRestrictionBanner extends StatelessWidget {
  const _DriverRestrictionBanner({required this.state});

  final DriverRestrictionMonitorState state;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final inside = state.phase == DriverRestrictionPhase.inside;
    final background = inside
        ? Theme.of(context).colorScheme.errorContainer
        : semantic.warningContainer;
    final foreground = inside
        ? Theme.of(context).colorScheme.onErrorContainer
        : semantic.onWarningContainer;
    return Material(
      key: const ValueKey('driver-restriction-app-banner'),
      color: background,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              inside ? Icons.report_rounded : Icons.warning_amber_rounded,
              color: foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (state.reportError?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      state.reportError!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: foreground),
                    ),
                  ],
                ],
              ),
            ),
            if (inside)
              TextButton(
                onPressed: () {
                  final violationId = state.violationId;
                  appRouter.push(
                    violationId == null
                        ? AppRoutes.driverViolations
                        : '${AppRoutes.driverViolations}/$violationId',
                  );
                },
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(state.reporting ? 'Sending…' : 'View'),
              ),
          ],
        ),
      ),
    );
  }
}
