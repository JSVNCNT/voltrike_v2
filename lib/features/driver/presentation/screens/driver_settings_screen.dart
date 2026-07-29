import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/settings_view.dart';

class DriverSettingsScreen extends StatelessWidget {
  const DriverSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Settings'),
      body: VolTrikeSettingsView(
        onEditPhoto: () => context.push(AppRoutes.editDriverProfile),
        onLogout: () => _logout(context),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await _confirmLogout(context);
    if (!shouldLogout) return;

    await AuthRepository().signOut();
    if (context.mounted) context.go(AppRoutes.intro);
  }
}

Future<bool> _confirmLogout(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.logout_rounded),
          title: const Text('Log out?'),
          content: const Text(
            'You will need to sign in again before receiving or managing rides.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Stay signed in'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Log out'),
            ),
          ],
        ),
      ) ??
      false;
}
