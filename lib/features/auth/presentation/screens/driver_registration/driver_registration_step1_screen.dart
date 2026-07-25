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
import '../../providers/driver_registration_data_provider.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/validation_message.dart';

class DriverRegistrationStep1Screen
    extends ConsumerStatefulWidget {
  const DriverRegistrationStep1Screen({
    super.key,
  });

  @override
  ConsumerState<DriverRegistrationStep1Screen>
      createState() =>
          _DriverRegistrationStep1ScreenState();
}

class _DriverRegistrationStep1ScreenState
    extends ConsumerState<
        DriverRegistrationStep1Screen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController =
      TextEditingController();

  final _middleNameController =
      TextEditingController();

  final _lastNameController =
      TextEditingController();

  final _birthDateController =
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

  DateTime? _dateOfBirth;

  String? _error;

  @override
  void initState() {
    super.initState();

    final registration =
        ref.read(driverRegistrationDataProvider);

    _firstNameController.text =
        registration.firstName;

    _middleNameController.text =
        registration.middleName;

    _lastNameController.text =
        registration.lastName;

    _dateOfBirth = registration.dateOfBirth;
    _birthDateController.text = _formatDate(
      registration.dateOfBirth,
    );

    _phoneController.text =
        registration.phoneNumber;

    _emailController.text =
        registration.email;

    _passwordController.text =
        registration.password;

    _confirmPasswordController.text =
        registration.password;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  void _continue() {
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

    if (_dateOfBirth == null) {
      setState(() {
        _error = 'Please select your date of birth.';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    ref
        .read(
          driverRegistrationDataProvider
              .notifier,
        )
        .updateData(
          firstName:
              _firstNameController.text.trim(),
          middleName:
              _middleNameController.text.trim(),
          lastName:
              _lastNameController.text.trim(),
          dateOfBirth: _dateOfBirth,
          phoneNumber:
              _phoneController.text.trim(),
          email:
              _emailController.text.trim(),
          password:
              _passwordController.text,
        );

    context.go(
      AppRoutes.driverRegisterStep2,
    );
  }

  String _formatDate(
    DateTime? value,
  ) {
    if (value == null) return '';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ??
          DateTime(
            today.year - 25,
            today.month,
            today.day,
          ),
      firstDate: DateTime(1900),
      lastDate: DateTime(
        today.year - 18,
        today.month,
        today.day,
      ),
      helpText: 'Select date of birth',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth = picked;
      _birthDateController.text = _formatDate(picked);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: false,
      child: AuthScaffold(
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
                    'Driver Registration',
                subtitle:
                    'Step 1 of 4\nPersonal Information',
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
                controller:
                    _firstNameController,
                label: 'First Name',
                hint: 'Juan',
                prefixIcon:
                    Icons.person_outline,
                textCapitalization:
                    TextCapitalization.words,
                textInputAction:
                    TextInputAction.next,
                validator: (value) =>
                    Validators.validateRequired(
                  value,
                  fieldName:
                      'First Name',
                ),
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              GestureDetector(
                onTap: _selectBirthDate,
                child: AbsorbPointer(
                  child: AppTextField(
                    controller: _birthDateController,
                    label: 'Date of Birth',
                    hint: 'YYYY-MM-DD',
                    prefixIcon: Icons.cake_outlined,
                    readOnly: true,
                    validator: (value) =>
                        value == null || value.isEmpty
                            ? 'Date of birth is required.'
                            : null,
                  ),
                ),
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              AppTextField(
                controller:
                    _middleNameController,
                label:
                    'Middle Name (Optional)',
                hint: 'Santos',
                prefixIcon:
                    Icons.person_outline,
                textCapitalization:
                    TextCapitalization.words,
                textInputAction:
                    TextInputAction.next,
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              AppTextField(
                controller:
                    _lastNameController,
                label: 'Last Name',
                hint: 'Dela Cruz',
                prefixIcon:
                    Icons.person_outline,
                textCapitalization:
                    TextCapitalization.words,
                textInputAction:
                    TextInputAction.next,
                validator: (value) =>
                    Validators.validateRequired(
                  value,
                  fieldName:
                      'Last Name',
                ),
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),
                            AppTextField(
                controller: _phoneController,
                label: AppStrings.phoneNumber,
                hint: '09XXXXXXXXX',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.next,
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
                prefixIcon: Icons.email_outlined,
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
                hint: 'Minimum 8 characters',
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
                textInputAction:
                    TextInputAction.done,
                validator: (value) =>
                    Validators
                        .validateConfirmPassword(
                  value,
                  _passwordController.text,
                ),
                onFieldSubmitted: (_) {
                  _continue();
                },
              ),

              const SizedBox(
                height: AppSpacing.lg,
              ),

              CheckboxListTile(
                value: _acceptedTerms,
                contentPadding:
                    EdgeInsets.zero,
                controlAffinity:
                    ListTileControlAffinity.leading,
                onChanged: (value) {
                  setState(() {
                    _acceptedTerms =
                        value ?? false;
                  });
                },
                title: const Text(
                  'I agree to the Terms & Conditions and Privacy Policy.',
                ),
              ),

              const SizedBox(
                height: AppSpacing.lg,
              ),

              PrimaryButton(
                text: AppStrings.continueText,
                onPressed: _continue,
              ),

              const SizedBox(
                height: AppSpacing.lg,
              ),

              TextButton(
                onPressed: () {
                  context.go(
                    AppRoutes.login,
                  );
                },
                child: const Text(
                  'Already have an account? Login',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
