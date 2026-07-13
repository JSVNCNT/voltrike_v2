import 'dart:async';

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
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/countdown_timer.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class EmailVerificationScreen
    extends ConsumerStatefulWidget {
  const EmailVerificationScreen({
    super.key,
  });

  @override
  ConsumerState<EmailVerificationScreen>
      createState() =>
          _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<
        EmailVerificationScreen> {
  Timer? _timer;

  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        _refreshStatus();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _message = null;
      _error = null;
    });

    try {
      final verified = await ref
          .read(
            emailVerificationControllerProvider
                .notifier,
          )
          .refreshVerification();

      if (!mounted) return;

      if (verified) {
        _timer?.cancel();

        context.go(
          AppRoutes.splash,
        );
      } else {
        setState(() {
          _message =
              'Waiting for email verification...';
        });
      }
    } catch (e) {
      setState(() {
        _error = e
            .toString()
            .replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _message = null;
      _error = null;
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
            'Verification email sent successfully.';
      });
    } catch (e) {
      setState(() {
        _error = e
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
              radius: 44,
              backgroundColor:
                  AppColors.primary,
              child: Icon(
                Icons.mark_email_read_outlined,
                color: Colors.white,
                size: 44,
              ),
            ),

            const SizedBox(
              height: AppSpacing.xl,
            ),

            const AuthHeader(
              title: AppStrings.verifyEmail,
              subtitle:
                  'A verification email has been sent.\nPlease verify your account to continue.',
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            Text(
              'Once your email has been verified, VolTrike will automatically continue.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            if (_error != null) ...[
              ValidationMessage(
                message: _error!,
              ),
              const SizedBox(
                height: AppSpacing.md,
              ),
            ],

            if (_message != null) ...[
              ValidationMessage(
                message: _message!,
                type: ValidationType.success,
              ),
              const SizedBox(
                height: AppSpacing.md,
              ),
            ],
                        CountdownTimer(
              seconds: 60,
              onFinished: () {},
            ),

            const SizedBox(
              height: AppSpacing.md,
            ),

            PrimaryButton(
              text: AppStrings.resendVerification,
              onPressed: _resendEmail,
              isLoading: state.isLoading,
            ),

            const SizedBox(
              height: AppSpacing.md,
            ),

            OutlinedButton.icon(
              onPressed: _refreshStatus,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Refresh Status',
              ),
            ),

            const SizedBox(
              height: AppSpacing.lg,
            ),

            TextButton.icon(
              onPressed: () {
                _timer?.cancel();

                context.go(
                  AppRoutes.login,
                );
              },
              icon: const Icon(
                Icons.arrow_back,
              ),
              label: const Text(
                AppStrings.login,
              ),
            ),

            const SizedBox(
              height: AppSpacing.xl,
            ),

             Text(
  'If you cannot find the email, check your Spam or Junk folder.',
  textAlign: TextAlign.center,
  style: AppTextStyles.bodyMedium.copyWith(
    color: Colors.grey,
  ),
),

          ],
        ),
      ),
    );
  }
}