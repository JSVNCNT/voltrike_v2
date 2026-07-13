import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_strings.dart';
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

class PassengerRegistrationSuccessScreen
    extends ConsumerStatefulWidget {
  const PassengerRegistrationSuccessScreen({
    super.key,
  });

  @override
  ConsumerState<PassengerRegistrationSuccessScreen>
      createState() =>
          _PassengerRegistrationSuccessScreenState();
}

class _PassengerRegistrationSuccessScreenState
    extends ConsumerState<
        PassengerRegistrationSuccessScreen> {
  String? _message;

  Future<void> _resendVerification() async {
    setState(() {
      _message = null;
    });

    try {
      await ref
          .read(
            emailVerificationControllerProvider
                .notifier,
          )
          .resendVerificationEmail();

      if (!mounted) return;

      setState(() {
        _message =
            'Verification email has been sent again.';
      });
    } catch (e) {
      setState(() {
        _message = e
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      emailVerificationControllerProvider,
    );

    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: Column(
          children: [
            const SizedBox(
              height: AppSpacing.lg,
            ),

            const AuthLogo(
              logoSize: 90,
            ),

            const SizedBox(
              height: AppSpacing.xl,
            ),

            const CircleAvatar(
              radius: 42,
              backgroundColor: AppColors.success,
              child: Icon(
                Icons.check,
                color: Colors.white,
                size: 48,
              ),
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            const AuthHeader(
              title: 'Account Created!',
              subtitle:
                  'Your passenger account has been created successfully.',
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            Text(
              'A verification email has been sent to your email address.\n\nPlease verify your email before logging in.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            if (_message != null) ...[
              ValidationMessage(
                message: _message!,
              ),
              const SizedBox(
                height: AppSpacing.md,
              ),
            ],

            PrimaryButton(
              text: 'Continue',
              onPressed: () {
                context.go(
                  AppRoutes.emailVerification,
                );
              },
            ),

            const SizedBox(
              height: AppSpacing.md,
            ),

            TextButton(
              onPressed: _resendVerification,
              child: const Text(
                'Resend Verification Email',
              ),
            ),

            const SizedBox(
              height: AppSpacing.md,
            ),

            AuthFooter(
              text: '',
              actionText: AppStrings.login,
              onPressed: () {
                context.go(
                  AppRoutes.login,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}