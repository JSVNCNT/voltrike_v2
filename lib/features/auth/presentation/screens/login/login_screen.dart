import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../../core/widgets/inputs/password_field.dart';
import '../../providers/login_provider.dart';
import '../../widgets/auth_footer.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() =>
      _LoginScreenState();
}

class _LoginScreenState
    extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController =
      TextEditingController();

  final _passwordController =
      TextEditingController();

  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _error = null;
    });

    try {
      final appUser = await ref
          .read(loginControllerProvider.notifier)
          .login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      if (!mounted || appUser == null) {
        return;
      }

      // ==========================================================
      // Passenger
      // ==========================================================

      if (appUser.isPassenger) {
        context.go(AppRoutes.splash);
        return;
      }

      // ==========================================================
      // Driver
      // ==========================================================

      if (appUser.isDriver) {
  context.go(
    AppRoutes.splash,
  );
  return;
}

      // ==========================================================
      // Admin Accounts
      // (Handled by the Web Portal)
      // ==========================================================

      if (appUser.isDeveloperAdmin ||
          appUser.isTodaAdmin) {
        setState(() {
          _error =
              'Administrator accounts use the VolTrike Web Portal.';
        });
        return;
      }

      // ==========================================================
      // Unknown Role
      // ==========================================================

      setState(() {
        _error =
            'Your account does not have a valid role.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(loginControllerProvider);

    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(
                height: AppSpacing.lg,
              ),

              const AuthLogo(
                logoSize: 100,
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              const AuthHeader(
                title: AppStrings.welcomeBack,
                subtitle:
                    AppStrings.loginSubtitle,
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              if (_error != null) ...[
                ValidationMessage(
                  message: _error!,
                ),
                const SizedBox(
                  height: AppSpacing.md,
                ),
              ],

              AppTextField(
                controller: _emailController,
                label: AppStrings.email,
                hint: 'example@email.com',
                prefixIcon:
                    Icons.email_outlined,
                keyboardType:
                    TextInputType.emailAddress,
                textInputAction:
                    TextInputAction.next,
                validator:
                    Validators.validateEmail,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              PasswordField(
                controller:
                    _passwordController,
                label: AppStrings.password,
                hint:
                    'Enter your password',
                textInputAction:
                    TextInputAction.done,
                validator:
                    Validators.validatePassword,
                onFieldSubmitted: (_) {
                  _login();
                },
              ),

              Align(
                alignment:
                    Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    context.go(
                      AppRoutes
                          .forgotPassword,
                    );
                  },
                  child: const Text(
                    AppStrings
                        .forgotPassword,
                  ),
                ),
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              PrimaryButton(
                text: AppStrings.login,
                onPressed: _login,
                isLoading:
                    state.isLoading,
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              AuthFooter(
                text: AppStrings
                    .dontHaveAccount,
                actionText: AppStrings
                    .registerPassenger,
                onPressed: () {
                  context.go(
                    AppRoutes
                        .passengerRegister,
                  );
                },
              ),

              const SizedBox(
                height: AppSpacing.sm,
              ),

              AuthFooter(
                text: '',
                actionText: AppStrings
                    .registerDriver,
                onPressed: () {
                  context.go(
                    AppRoutes
                        .driverRegister,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
