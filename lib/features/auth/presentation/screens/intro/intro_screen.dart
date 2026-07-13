import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),

          const AuthLogo(),

          const SizedBox(height: AppSpacing.xxl),

          PrimaryButton(
            text: 'Login',
            onPressed: () {
              context.go(AppRoutes.login);
            },
          ),

          const SizedBox(height: AppSpacing.md),

          OutlinedPrimaryButton(
            text: 'Register as Passenger',
            onPressed: () {
              context.go(AppRoutes.passengerRegister);
            },
          ),

          const SizedBox(height: AppSpacing.md),

          OutlinedPrimaryButton(
            text: 'Register as Driver',
            onPressed: () {
              context.go(AppRoutes.driverRegister);
            },
          ),
        ],
      ),
    );
  }
}