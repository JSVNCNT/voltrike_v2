import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';

import '../../providers/driver_registration_data_provider.dart';
import '../../providers/driver_registration_provider.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/document_picker_card.dart';
import '../../widgets/image_preview.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/registration_step_indicator.dart';
import '../../widgets/validation_message.dart';

class UploadDocumentsScreen extends ConsumerStatefulWidget {
  const UploadDocumentsScreen({super.key});

  @override
  ConsumerState<UploadDocumentsScreen> createState() =>
      _UploadDocumentsScreenState();
}

class _UploadDocumentsScreenState extends ConsumerState<UploadDocumentsScreen> {
  final ImagePicker _picker = ImagePicker();

  File? _profilePhoto;

  File? _licenseFront;

  File? _licenseBack;

  File? _governmentId;

  File? _orDocument;

  File? _crDocument;

  File? _vehiclePhoto;

  String? _error;

  Future<void> _pickImage(void Function(File file) setter) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image == null) {
      return;
    }

    setter(File(image.path));

    if (mounted) {
      setState(() {});
    }
  }

  bool get _isComplete {
    return _profilePhoto != null &&
        _licenseFront != null &&
        _licenseBack != null &&
        _governmentId != null &&
        _orDocument != null &&
        _crDocument != null &&
        _vehiclePhoto != null;
  }

  Future<void> _submit() async {
    if (!_isComplete) {
      setState(() {
        _error = 'Please upload all required documents.';
      });

      return;
    }

    setState(() {
      _error = null;
    });

    ref
        .read(driverRegistrationDataProvider.notifier)
        .updateData(
          profilePhoto: _profilePhoto!.path,
          driverLicenseFront: _licenseFront!.path,
          driverLicenseBack: _licenseBack!.path,
          governmentId: _governmentId!.path,
          orDocument: _orDocument!.path,
          crDocument: _crDocument!.path,
          vehiclePhoto: _vehiclePhoto!.path,
        );

    final registration = ref.read(driverRegistrationDataProvider);

    try {
      await ref
          .read(driverRegistrationControllerProvider.notifier)
          .register(registration);

      if (!mounted) {
        return;
      }

      context.go(AppRoutes.driverUnderReview);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = DomainErrorMapper.message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverRegistrationControllerProvider);
    return LoadingOverlay(
      isLoading: state.isLoading,
      child: AuthScaffold(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const AuthLogo(logoSize: 72),

              const SizedBox(height: AppSpacing.xl),

              const AuthHeader(
                title: 'Driver registration',
                subtitle: 'Required documents for TODA review',
              ),

              const SizedBox(height: AppSpacing.lg),
              const RegistrationStepIndicator(currentStep: 4, totalSteps: 4),
              const SizedBox(height: AppSpacing.lg),

              if (_error != null) ...[
                ValidationMessage(message: _error!),
                const SizedBox(height: AppSpacing.md),
              ],

              //--------------------------------------------------
              // Profile Photo
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Profile Photo',
                icon: Icons.person,
                file: _profilePhoto,
                onTap: () => _pickImage((file) => _profilePhoto = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _profilePhoto),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Driver License Front
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Driver License (Front)',
                icon: Icons.badge_outlined,
                file: _licenseFront,
                onTap: () => _pickImage((file) => _licenseFront = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _licenseFront),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Driver License Back
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Driver License (Back)',
                icon: Icons.badge,
                file: _licenseBack,
                onTap: () => _pickImage((file) => _licenseBack = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _licenseBack),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Government ID
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Government ID',
                icon: Icons.credit_card,
                file: _governmentId,
                onTap: () => _pickImage((file) => _governmentId = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _governmentId),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Official Receipt (OR)
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Official Receipt (OR)',
                icon: Icons.receipt_long,
                file: _orDocument,
                onTap: () => _pickImage((file) => _orDocument = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _orDocument),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Certificate of Registration (CR)
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Certificate of Registration (CR)',
                icon: Icons.description,
                file: _crDocument,
                onTap: () => _pickImage((file) => _crDocument = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _crDocument),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Vehicle Photo
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Vehicle Photo',
                icon: Icons.directions_car,
                file: _vehiclePhoto,
                onTap: () => _pickImage((file) => _vehiclePhoto = file),
              ),

              const SizedBox(height: AppSpacing.sm),

              ImagePreview(file: _vehiclePhoto),

              const SizedBox(height: AppSpacing.xl),

              //--------------------------------------------------
              // Submit
              //--------------------------------------------------
              PrimaryButton(
                text: 'Submit Registration',
                onPressed: _submit,
                isLoading: state.isLoading,
              ),

              const SizedBox(height: AppSpacing.md),

              TextButton.icon(
                onPressed: state.isLoading
                    ? null
                    : () {
                        context.go(AppRoutes.driverRegisterStep3);
                      },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text(
                state.isLoading
                    ? 'Creating your account... Please wait.'
                    : 'By submitting your registration, you agree that '
                          'VolTrike may review your documents before approving your account.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
