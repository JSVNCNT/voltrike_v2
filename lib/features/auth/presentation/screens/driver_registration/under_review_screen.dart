import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class DriverUnderReviewScreen extends ConsumerWidget {
  const DriverUnderReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthScaffold(
      child: Column(
        children: [
          const AuthLogo(logoSize: 68),
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              size: 36,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AuthHeader(
            title: 'Application under review',
            subtitle:
                'Your registration and documents were submitted to your TODA.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                children: [
                  _ReviewStep(
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    label: 'Registration submitted',
                  ),
                  Divider(height: 28),
                  _ReviewStep(
                    icon: Icons.mark_email_read_outlined,
                    color: AppColors.primary,
                    label: 'Verification email sent',
                  ),
                  Divider(height: 28),
                  _ReviewStep(
                    icon: Icons.description_outlined,
                    color: AppColors.warning,
                    label: 'Documents awaiting review',
                  ),
                  Divider(height: 28),
                  _ReviewStep(
                    icon: Icons.groups_outlined,
                    color: AppColors.primaryDark,
                    label: 'TODA approval pending',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Verify your email and wait for approval. Account access will update '
            'when your TODA completes its review.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            text: 'Return to sign in',
            icon: Icons.login_rounded,
            onPressed: () => context.go(AppRoutes.login),
          ),
        ],
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}
