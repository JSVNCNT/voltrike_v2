import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_logo.dart';
import '../widgets/auth_scaffold.dart';

class RegistrationPreparationScreen extends StatelessWidget {
  const RegistrationPreparationScreen({super.key, required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final requirements = isDriver
        ? const <(IconData, String)>[
            (Icons.person, 'Profile photo'),
            (Icons.badge_outlined, "Driver’s license — front"),
            (Icons.badge, "Driver’s license — back"),
            (Icons.credit_card, 'Government ID'),
            (Icons.receipt_long, 'Vehicle Official Receipt (OR)'),
            (Icons.description, 'Certificate of Registration (CR)'),
            (Icons.directions_car, 'Vehicle photo'),
            (Icons.groups_outlined, 'Your TODA and vehicle details'),
          ]
        : const <(IconData, String)>[
            (Icons.person_outline, 'Your name and mobile number'),
            (Icons.email_outlined, 'An email address you can verify'),
            (Icons.lock_outline, 'A secure password'),
          ];
    return AuthScaffold(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthLogo(),
            const SizedBox(height: AppSpacing.lg),
            AuthHeader(
              title: 'Before you begin',
              subtitle: isDriver
                  ? 'Please prepare these requirements before starting your driver application. Keep your documents clear, readable, and current.'
                  : 'Have these details ready to create your passenger account.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Column(
                children: [
                  for (final (icon, label) in requirements)
                    ListTile(
                      leading: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isDriver
                  ? 'Document photos must be taken using your camera. Profile and vehicle photos can also come from your gallery. Your assigned TODA will review your application before you can accept rides.'
                  : 'You will be asked to review the Terms and Conditions and Privacy Policy before registering.',
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              text: 'Continue registration',
              onPressed: () => context.go(
                isDriver
                    ? AppRoutes.driverRegisterStep1
                    : AppRoutes.passengerRegister,
              ),
            ),
            TextButton(
              onPressed: () => context.go(AppRoutes.intro),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
