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
import '../../widgets/registration_back_scope.dart';
import '../../widgets/registration_step_indicator.dart';
import '../../widgets/validation_message.dart';

class DriverRegistrationStep1Screen extends ConsumerStatefulWidget {
  const DriverRegistrationStep1Screen({super.key, this.returnToReview = false});

  final bool returnToReview;

  @override
  ConsumerState<DriverRegistrationStep1Screen> createState() =>
      _DriverRegistrationStep1ScreenState();
}

class _DriverRegistrationStep1ScreenState
    extends ConsumerState<DriverRegistrationStep1Screen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();

  final _middleNameController = TextEditingController();

  final _lastNameController = TextEditingController();

  final _birthDateController = TextEditingController();

  final _phoneController = TextEditingController();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  final _confirmPasswordController = TextEditingController();

  DateTime? _dateOfBirth;

  String? _error;

  @override
  void initState() {
    super.initState();

    final registration = ref.read(driverRegistrationDataProvider);

    _firstNameController.text = registration.firstName;

    _middleNameController.text = registration.middleName;

    _lastNameController.text = registration.lastName;

    _dateOfBirth = registration.dateOfBirth;
    _birthDateController.text = _formatDate(registration.dateOfBirth);

    _phoneController.text = registration.phoneNumber;

    _emailController.text = registration.email;

    _passwordController.text = registration.password;

    _confirmPasswordController.text = registration.password;
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

    if (_dateOfBirth == null) {
      setState(() {
        _error = 'Please select your date of birth.';
      });
      return;
    }

    if (!_isAtLeast18(_dateOfBirth!)) {
      setState(() {
        _error =
            'Driver applicants must be at least 18 years old on the date of '
            'registration.';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    ref
        .read(driverRegistrationDataProvider.notifier)
        .updateData(
          firstName: _firstNameController.text.trim(),
          middleName: _middleNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          dateOfBirth: _dateOfBirth,
          phoneNumber: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    context.go(
      widget.returnToReview
          ? AppRoutes.driverRegisterReview
          : AppRoutes.driverRegisterStep2,
    );
  }

  bool _isAtLeast18(DateTime birthDate) {
    final today = DateUtils.dateOnly(DateTime.now());
    final eighteenthBirthday = DateTime(
      birthDate.year + 18,
      birthDate.month,
      birthDate.day,
    );
    return !eighteenthBirthday.isAfter(today);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 25, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(today.year - 18, today.month, today.day),
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
    return RegistrationBackScope(
      fallbackRoute: widget.returnToReview
          ? AppRoutes.driverRegisterReview
          : AppRoutes.intro,
      child: LoadingOverlay(
        isLoading: false,
        child: AuthScaffold(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const AuthLogo(logoSize: 72),

                const SizedBox(height: AppSpacing.xl),

                const AuthHeader(
                  title: 'Driver registration',
                  subtitle: 'Personal and account information',
                ),

                const SizedBox(height: AppSpacing.lg),
                const RegistrationStepIndicator(currentStep: 1, totalSteps: 5),
                const SizedBox(height: AppSpacing.xl),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Drivers must be 18 or older'),
                    subtitle: const Text(
                      'Date of birth is collected to confirm the minimum age for '
                      'professional driving and will be reviewed with your ID.',
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                if (_error != null) ...[
                  ValidationMessage(message: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppTextField(
                  controller: _firstNameController,
                  label: 'First Name',
                  hint: 'Juan',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) => Validators.validateRequired(
                    value,
                    fieldName: 'First Name',
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  controller: _middleNameController,
                  label: 'Middle Name (Optional)',
                  hint: 'Santos',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  controller: _lastNameController,
                  label: 'Last Name',
                  hint: 'Dela Cruz',
                  prefixIcon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (value) => Validators.validateRequired(
                    value,
                    fieldName: 'Last Name',
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                GestureDetector(
                  onTap: _selectBirthDate,
                  child: AbsorbPointer(
                    child: AppTextField(
                      controller: _birthDateController,
                      label: 'Date of Birth',
                      hint: 'YYYY-MM-DD',
                      prefixIcon: Icons.cake_outlined,
                      readOnly: true,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Date of birth is required.'
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  controller: _phoneController,
                  label: AppStrings.phoneNumber,
                  hint: '09XXXXXXXXX',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  validator: Validators.validatePhoneNumber,
                ),

                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  controller: _emailController,
                  label: AppStrings.email,
                  hint: 'example@email.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: Validators.validateEmail,
                ),

                const SizedBox(height: AppSpacing.md),

                PasswordField(
                  controller: _passwordController,
                  label: AppStrings.password,
                  hint: 'Minimum 8 characters',
                  textInputAction: TextInputAction.next,
                  validator: Validators.validatePassword,
                ),

                const SizedBox(height: AppSpacing.md),

                PasswordField(
                  controller: _confirmPasswordController,
                  label: AppStrings.confirmPassword,
                  hint: 'Re-enter your password',
                  textInputAction: TextInputAction.done,
                  validator: (value) => Validators.validateConfirmPassword(
                    value,
                    _passwordController.text,
                  ),
                  onFieldSubmitted: (_) {
                    _continue();
                  },
                ),

                const SizedBox(height: AppSpacing.lg),

                PrimaryButton(
                  text: widget.returnToReview
                      ? 'Save changes'
                      : AppStrings.continueText,
                  onPressed: _continue,
                ),

                const SizedBox(height: AppSpacing.lg),

                TextButton(
                  onPressed: () {
                    context.go(
                      widget.returnToReview
                          ? AppRoutes.driverRegisterReview
                          : AppRoutes.login,
                    );
                  },
                  child: Text(
                    widget.returnToReview
                        ? 'Cancel and return to review'
                        : 'Already have an account? Login',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
