import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../data/repositories/auth_repository.dart';
import '../../providers/email_verification_provider.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/validation_message.dart';

class DriverUnderReviewScreen extends ConsumerStatefulWidget {
  const DriverUnderReviewScreen({super.key});

  @override
  ConsumerState<DriverUnderReviewScreen> createState() =>
      _DriverUnderReviewScreenState();
}

class _DriverUnderReviewScreenState
    extends ConsumerState<DriverUnderReviewScreen> {
  bool _isSending = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _sendVerification() async {
    setState(() {
      _isSending = true;
      _message = null;
      _messageIsError = false;
    });

    try {
      final controller = ref.read(emailVerificationControllerProvider.notifier);
      final delivery = await controller.resendVerificationEmail();
      if (!mounted) return;
      setState(() {
        _message = switch (delivery) {
          VerificationEmailDelivery.branded =>
            'Verification email sent. Check your inbox and Spam or Junk folder.',
          VerificationEmailDelivery.firebaseFallback =>
            'Verification email sent through Firebase. Check your inbox and Spam or Junk folder.',
          VerificationEmailDelivery.alreadyVerified =>
            'Email verified. Your driver access will activate after TODA approval.',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = DomainErrorMapper.message(error);
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    label: 'Email verification optional',
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
            'Email verification is optional during private testing but is '
            'recommended for account recovery. Driver access updates when '
            'your TODA completes its review.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ValidationMessage(
              message: _message!,
              type: _messageIsError
                  ? ValidationType.error
                  : ValidationType.success,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            text: 'Resend verification email',
            icon: Icons.mark_email_read_outlined,
            isLoading: _isSending,
            onPressed: _isSending ? null : _sendVerification,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            label: const Text('Return to sign in'),
            icon: const Icon(Icons.login_rounded),
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
