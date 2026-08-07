import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../providers/email_verification_provider.dart';
import '../../widgets/auth_footer.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class PassengerRegistrationSuccessScreen extends ConsumerStatefulWidget {
  const PassengerRegistrationSuccessScreen({super.key});

  @override
  ConsumerState<PassengerRegistrationSuccessScreen> createState() =>
      _PassengerRegistrationSuccessScreenState();
}

class _PassengerRegistrationSuccessScreenState
    extends ConsumerState<PassengerRegistrationSuccessScreen> {
  String? _message;
  bool _messageIsError = false;

  Future<void> _resendVerification() async {
    setState(() {
      _message = null;
      _messageIsError = false;
    });

    try {
      await ref
          .read(emailVerificationControllerProvider.notifier)
          .resendVerificationEmail();

      if (!mounted) return;

      setState(() {
        _message = 'Verification email has been sent again.';
      });
    } catch (e) {
      setState(() {
        _message = DomainErrorMapper.message(e);
        _messageIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailVerificationControllerProvider);

    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: Column(
          children: [
            const AuthLogo(logoSize: 68),

            const SizedBox(height: AppSpacing.xl),

            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.success,
                size: 38,
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const AuthHeader(
              title: 'Passenger account created',
              subtitle: 'Your private testing account is ready to sign in.',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: AppSpacing.lg),

            Text(
              'A verification email was requested for account recovery. '
              'You can sign in now while this private testing build keeps '
              'email verification optional.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),

            const SizedBox(height: AppSpacing.lg),

            if (_message != null) ...[
              ValidationMessage(
                message: _message!,
                type: _messageIsError
                    ? ValidationType.error
                    : ValidationType.success,
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            PrimaryButton(
              text: 'Continue to verification',
              icon: Icons.mark_email_read_outlined,
              onPressed: () {
                context.go(AppRoutes.emailVerification);
              },
            ),

            const SizedBox(height: AppSpacing.md),

            TextButton(
              onPressed: _resendVerification,
              child: const Text('Resend Verification Email'),
            ),

            const SizedBox(height: AppSpacing.md),

            AuthFooter(
              text: '',
              actionText: AppStrings.login,
              onPressed: () {
                context.go(AppRoutes.login);
              },
            ),
          ],
        ),
      ),
    );
  }
}
