import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Gives registration screens a deterministic system-back destination.
///
/// The registration wizard uses [GoRouter.go], which replaces the current
/// route instead of building a native navigation stack. Intercepting system
/// back prevents Android from closing the app when a previous wizard step is
/// available.
class RegistrationBackScope extends StatelessWidget {
  const RegistrationBackScope({
    super.key,
    required this.fallbackRoute,
    required this.child,
  });

  final String fallbackRoute;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallbackRoute);
      },
      child: child,
    );
  }
}
