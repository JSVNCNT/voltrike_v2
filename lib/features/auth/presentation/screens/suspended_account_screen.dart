import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/repositories/auth_repository.dart';

class SuspendedAccountScreen extends StatelessWidget {
  const SuspendedAccountScreen({super.key, required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    size: 88,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Account suspended',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isDriver
                        ? 'Your driving access is paused while the report is '
                              'evaluated by your TODA and the VolTrike '
                              'developer administrator.'
                        : 'Your passenger access is paused while the report is '
                              'evaluated by the VolTrike developer '
                              'administrator.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This screen updates automatically when administrators '
                    'restore your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await AuthRepository().signOut();
                      if (context.mounted) context.go(AppRoutes.login);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
