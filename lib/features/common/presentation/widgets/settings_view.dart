import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import 'profile_widgets.dart';
import 'system_diagnostics_tile.dart';

class VolTrikeSettingsView extends StatelessWidget {
  const VolTrikeSettingsView({
    super.key,
    required this.onEditPhoto,
    required this.onLogout,
  });

  final VoidCallback onEditPhoto;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ProfileSection(
          title: 'Account',
          children: [
            ListTile(
              minTileHeight: 64,
              leading: const Icon(
                Icons.account_circle_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Change profile photo'),
              subtitle: const Text('Choose a new account photo'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onEditPhoto,
            ),
            const SystemDiagnosticsTile(),
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
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: const Text(
                'Log out',
                style: TextStyle(
                  color: AppColors.error,
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
