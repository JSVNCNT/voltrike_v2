import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../core/widgets/inputs/app_text_field.dart';
import '../../providers/forgot_password_provider.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();

  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _message = null;
      _error = null;
    });

    try {
      await ref
          .read(forgotPasswordControllerProvider.notifier)
          .sendResetEmail(_emailController.text.trim());

      if (!mounted) return;

      setState(() {
        _message =
            'If an account exists for that email, a password reset link '
            'will arrive shortly.';
      });
    } catch (e) {
      setState(() => _error = DomainErrorMapper.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forgotPasswordControllerProvider);

    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const AuthLogo(logoSize: 72),

              const SizedBox(height: AppSpacing.xl),

              const AuthHeader(
                title: 'Reset your password',
                subtitle:
                    'We will email a secure reset link to your account address.',
              ),

              const SizedBox(height: AppSpacing.xl),

              if (_error != null) ...[
                ValidationMessage(message: _error!),
                const SizedBox(height: AppSpacing.md),
              ],

              if (_message != null) ...[
                ValidationMessage(
                  message: _message!,
                  type: ValidationType.success,
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              AppTextField(
                controller: _emailController,
                label: AppStrings.email,
                hint: 'example@email.com',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: Validators.validateEmail,
              ),

              const SizedBox(height: AppSpacing.xl),

              PrimaryButton(
                text: AppStrings.sendResetLink,
                icon: Icons.mark_email_read_outlined,
                onPressed: _sendResetLink,
                isLoading: state.isLoading,
              ),

              const SizedBox(height: AppSpacing.lg),

              TextButton.icon(
                onPressed: () {
                  context.go(AppRoutes.login);
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text(AppStrings.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
