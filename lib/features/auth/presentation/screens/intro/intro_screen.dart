import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        children: [
          const AuthLogo(),
          const SizedBox(height: AppSpacing.xl),
          const AuthHeader(
            title: 'Welcome to VolTrike',
            subtitle:
                'Reliable community rides for passengers and accredited drivers.',
          ),
          const SizedBox(height: AppSpacing.xl),

          PrimaryButton(
            text: 'Sign in',
            icon: Icons.login_rounded,
            onPressed: () {
              context.go(AppRoutes.login);
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Create an account',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),

          OutlinedPrimaryButton(
            text: 'Continue as passenger',
            icon: Icons.person_outline_rounded,
            onPressed: () {
              context.go(AppRoutes.passengerPrepare);
            },
          ),

          const SizedBox(height: AppSpacing.md),

          OutlinedPrimaryButton(
            text: 'Apply as a driver',
            icon: Icons.electric_rickshaw_outlined,
            onPressed: () {
              context.go(AppRoutes.driverRegister);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Driver applications require TODA, license, vehicle, and document review.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
