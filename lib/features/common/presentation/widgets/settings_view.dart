import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/providers/theme_provider.dart';
import 'profile_widgets.dart';
import 'system_diagnostics_tile.dart';

class VolTrikeSettingsView extends ConsumerWidget {
  const VolTrikeSettingsView({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final darkMode = ref.watch(themeModeProvider) == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ProfileSection(
          title: 'Account',
          children: const [SystemDiagnosticsTile()],
        ),
        const SizedBox(height: 24),
        ProfileSection(
          title: 'Appearance',
          children: [
            SwitchListTile(
              minTileHeight: 68,
              secondary: Icon(
                darkMode ? Icons.dark_mode_rounded : Icons.light_mode_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Dark mode'),
              subtitle: Text(
                darkMode
                    ? 'Use the darker VolTrike theme'
                    : 'Use the light VolTrike theme',
              ),
              value: darkMode,
              onChanged: (enabled) async {
                final saved = await ref
                    .read(themeModeProvider.notifier)
                    .setDarkMode(enabled);
                if (!saved && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Theme preference could not be saved. Try again.',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        ProfileSection(
          title: 'About and legal',
          children: [
            ListTile(
              minTileHeight: 60,
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About VolTrike'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.aboutVoltrike),
            ),
            ListTile(
              minTileHeight: 60,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.privacyPolicy),
            ),
            ListTile(
              minTileHeight: 60,
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms and conditions'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.termsAndConditions),
            ),
            ListTile(
              minTileHeight: 60,
              leading: const Icon(Icons.balance_outlined),
              title: const Text('Map and open-source licenses'),
              subtitle: const Text('Google Navigation and app licenses'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'VolTrike',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ProfileSection(
          title: 'Session',
          children: [
            ListTile(
              minTileHeight: 60,
              leading: Icon(Icons.logout_rounded, color: colorScheme.error),
              title: Text(
                'Log out',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Sign out of this device'),
              onTap: onLogout,
            ),
          ],
        ),
      ],
    );
  }
}
