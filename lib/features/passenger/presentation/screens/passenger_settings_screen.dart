import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../core/services/location_service.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/settings_view.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/booking_session_provider.dart';
import '../../providers/passenger_location_provider.dart';

class PassengerSettingsScreen extends ConsumerWidget {
  const PassengerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Settings'),
      body: VolTrikeSettingsView(
        onEditPhoto: () => context.push(AppRoutes.editPassengerProfile),
        onLogout: () => _logout(context, ref),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final shouldLogout = await _confirmLogout(context);
    if (!shouldLogout) return;

    await LocationService.instance.stopTracking();
    ref.invalidate(passengerLocationProvider);
    ref.invalidate(bookingControllerProvider);
    ref.read(bookingProvider.notifier).reset();
    ref.read(bookingSessionProvider.notifier).reset();
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
            'You will need to sign in again to request and manage rides.',
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
