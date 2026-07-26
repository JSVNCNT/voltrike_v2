import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/system_diagnostics_tile.dart';

class DriverSettingsScreen extends StatelessWidget {
  const DriverSettingsScreen({
    super.key,
  });

  Future<void> _logout(
    BuildContext context,
  ) async {
    final shouldLogout =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Logout',
          ),
          content: const Text(
            'Are you sure you want to logout?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child: const Text(
                'Logout',
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    await AuthRepository().signOut();

    if (context.mounted) {
      context.go(
        AppRoutes.intro,
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: const AppAppBar(
        title: 'Settings',
      ),
      body: ListView(
        children: [
          const SizedBox(
            height: 12,
          ),

          //----------------------------------------------------------------
          // Account
          //----------------------------------------------------------------

          const ListTile(
            title: Text(
              'Account',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(
              Icons.edit_outlined,
            ),
            title: const Text(
              'Edit Profile',
            ),
            subtitle: const Text(
              'Update your profile photo',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {
              context.push(
                AppRoutes.editDriverProfile,
              );
            },
          ),

          const SystemDiagnosticsTile(),

          const Divider(),

          //----------------------------------------------------------------
          // Application
          //----------------------------------------------------------------

          const ListTile(
            title: Text(
              'Application',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(
              Icons.info_outline,
            ),
            title: const Text(
              'About Voltrike',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {
              context.push(
                AppRoutes.aboutVoltrike,
              );
            },
          ),

          ListTile(
            leading: const Icon(
              Icons.privacy_tip_outlined,
            ),
            title: const Text(
              'Privacy Policy',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {
              context.push(
                AppRoutes.privacyPolicy,
              );
            },
          ),

          ListTile(
            leading: const Icon(
              Icons.description_outlined,
            ),
            title: const Text(
              'Terms & Conditions',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {
              context.push(
                AppRoutes.termsAndConditions,
              );
            },
          ),

          const Divider(),

          //----------------------------------------------------------------
          // Session
          //----------------------------------------------------------------

          const ListTile(
            title: Text(
              'Session',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          ListTile(
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
            ),
            title: const Text(
              'Logout',
              style: TextStyle(
                color: Colors.red,
              ),
            ),
            onTap: () => _logout(
              context,
            ),
          ),

          const SizedBox(
            height: 24,
          ),

          const Center(
            child: Text(
              'Voltrike Driver v1.0.0',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ),

          const SizedBox(
            height: 20,
          ),
        ],
      ),
    );
  }
}
