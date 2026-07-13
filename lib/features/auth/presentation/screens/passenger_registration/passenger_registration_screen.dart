import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/utils/validators.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../../core/widgets/inputs/password_field.dart';
import '../../../../../data/models/app_user.dart';
import '../../../../../data/models/passenger.dart';
import '../../providers/passenger_registration_provider.dart';
import '../../widgets/auth_footer.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class PassengerRegistrationScreen
    extends ConsumerStatefulWidget {
  const PassengerRegistrationScreen({
    super.key,
  });

  @override
  ConsumerState<PassengerRegistrationScreen>
      createState() =>
          _PassengerRegistrationScreenState();
}

class _PassengerRegistrationScreenState
    extends ConsumerState<
        PassengerRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController =
      TextEditingController();

  final _middleNameController =
      TextEditingController();

  final _lastNameController =
      TextEditingController();

  final _phoneController =
      TextEditingController();

  final _emailController =
      TextEditingController();

  final _passwordController =
      TextEditingController();

  final _confirmPasswordController =
      TextEditingController();

  bool _acceptedTerms = false;

  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms) {
      setState(() {
        _error =
            'Please accept the Terms and Conditions.';
      });

      return;
    }

    setState(() {
      _error = null;
    });

    final now = DateTime.now();

    final appUser = AppUser(
      uid: '',
      email: _emailController.text.trim(),
      firstName:
          _firstNameController.text.trim(),
      middleName:
          _middleNameController.text.trim(),
      lastName:
          _lastNameController.text.trim(),
      phoneNumber:
          _phoneController.text.trim(),
      role: 'passenger',
      profileImage: '',
      emailVerified: false,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final passenger = Passenger(
      uid: '',
      favoriteLocations: const [],
      totalTrips: 0,
      rating: 0,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await ref
          .read(
            passengerRegistrationControllerProvider
                .notifier,
          )
          .register(
            user: appUser,
            passenger: passenger,
            password:
                _passwordController.text,
          );

      if (!mounted) return;

      context.go(
        AppRoutes.passengerRegisterSuccess,
      );
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
      passengerRegistrationControllerProvider,
    );

    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
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

                const AuthHeader(
                  title:
                      'Create Passenger Account',
                  subtitle:
                      'Create your VolTrike passenger account.',
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
                  controller: _firstNameController,
                  label: 'First Name',
                  hint: 'Juan',
                  prefixIcon: Icons.person_outline,
                  textCapitalization:
                      TextCapitalization.words,
                  autofillHints: const [
                    AutofillHints.givenName,
                  ],
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName: 'First name',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller: _middleNameController,
                  label: 'Middle Name (Optional)',
                  hint: 'Santos',
                  prefixIcon: Icons.person_outline,
                  textCapitalization:
                      TextCapitalization.words,
                  textInputAction:
                      TextInputAction.next,
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller: _lastNameController,
                  label: 'Last Name',
                  hint: 'Dela Cruz',
                  prefixIcon: Icons.person_outline,
                  textCapitalization:
                      TextCapitalization.words,
                  autofillHints: const [
                    AutofillHints.familyName,
                  ],
                  textInputAction:
                      TextInputAction.next,
                  validator: (value) =>
                      Validators.validateRequired(
                    value,
                    fieldName: 'Last name',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller: _phoneController,
                  label: AppStrings.phoneNumber,
                  hint: '09XXXXXXXXX',
                  prefixIcon:
                      Icons.phone_outlined,
                  keyboardType:
                      TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter
                        .digitsOnly,
                  ],
                  autofillHints: const [
                    AutofillHints
                        .telephoneNumber,
                  ],
                  textInputAction:
                      TextInputAction.next,
                  validator:
                      Validators.validatePhoneNumber,
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                AppTextField(
                  controller: _emailController,
                  label: AppStrings.email,
                  hint: 'example@email.com',
                  prefixIcon:
                      Icons.email_outlined,
                  keyboardType:
                      TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.email,
                  ],
                  autocorrect: false,
                  enableSuggestions: false,
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
                      'Minimum 8 characters',
                  autofillHints: const [
                    AutofillHints.newPassword,
                  ],
                  textInputAction:
                      TextInputAction.next,
                  validator:
                      Validators.validatePassword,
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),

                PasswordField(
                  controller:
                      _confirmPasswordController,
                  label:
                      AppStrings.confirmPassword,
                  hint:
                      'Re-enter your password',
                  autofillHints: const [
                    AutofillHints.newPassword,
                  ],
                  textInputAction:
                      TextInputAction.done,
                  validator: (value) =>
                      Validators
                          .validateConfirmPassword(
                    value,
                    _passwordController.text,
                  ),
                  onFieldSubmitted: (_) {
                    _register();
                  },
                ),

                const SizedBox(
                  height: AppSpacing.lg,
                ),

                CheckboxListTile(
                  value: _acceptedTerms,
                  onChanged: (value) {
                    setState(() {
                      _acceptedTerms =
                          value ?? false;
                    });
                  },
                  contentPadding:
                      EdgeInsets.zero,
                  controlAffinity:
                      ListTileControlAffinity
                          .leading,
                  title: const Text(
                    'I agree to the Terms and Conditions and Privacy Policy.',
                  ),
                ),

                const SizedBox(
                  height: AppSpacing.lg,
                ),
                                PrimaryButton(
                  text: AppStrings.createAccount,
                  onPressed: _register,
                  isLoading: state.isLoading,
                ),

                const SizedBox(
                  height: AppSpacing.xl,
                ),

                AuthFooter(
                  text: 'Already have an account?',
                  actionText: AppStrings.login,
                  onPressed: () {
                    context.go(
                      AppRoutes.login,
                    );
                  },
                ),

                const SizedBox(
                  height: AppSpacing.md,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}