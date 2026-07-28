import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../common/presentation/screens/legal/legal_document_versions.dart';

import '../../providers/driver_registration_data_provider.dart';
import '../../providers/driver_registration_provider.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/document_picker_card.dart';
import '../../widgets/image_preview.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/legal_consent_card.dart';
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

  bool _termsViewed = false;
  bool _privacyViewed = false;
  bool _acceptedLegal = false;

  String? _error;

  Future<void> _pickImage({
    required void Function(File file) setter,
    required double aspectRatio,
    required int targetWidth,
    required bool allowGallery,
  }) async {
    final source = allowGallery
        ? await showModalBottomSheet<ImageSource>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take photo'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          )
        : ImageSource.camera;
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 92,
        maxWidth: 2600,
        maxHeight: 2600,
      );
      if (picked == null) return;

      final processedPath = await Isolate.run(
        () => _prepareRegistrationImage(picked.path, aspectRatio, targetWidth),
      );
      final file = File(processedPath);
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException(
          'The processed image is larger than 4 MB. Retake it with better '
          'lighting and less background.',
        );
      }
      if (!mounted) return;
      setState(() {
        setter(file);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not prepare that image. Please try again.';
      });
    }
  }

  bool get _isComplete {
    return _profilePhoto != null &&
        _licenseFront != null &&
        _licenseBack != null &&
        _governmentId != null &&
        _orDocument != null &&
        _crDocument != null &&
        _vehiclePhoto != null &&
        _acceptedLegal;
  }

  Future<void> _submit() async {
    if (!_isComplete) {
      setState(() {
        _error = !_acceptedLegal
            ? 'Review and accept the Terms and Conditions and Privacy Policy.'
            : 'Please capture all required registration images.';
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
          termsAcceptedAt: DateTime.now(),
          privacyAcceptedAt: DateTime.now(),
          termsVersion: LegalDocumentVersions.terms,
          privacyVersion: LegalDocumentVersions.privacy,
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

  Future<void> _openLegalDocument({
    required String route,
    required bool terms,
  }) async {
    final confirmed = await context.push<bool>('$route?acknowledge=true');
    if (!mounted || confirmed != true) return;
    setState(() {
      if (terms) {
        _termsViewed = true;
      } else {
        _privacyViewed = true;
      }
      _acceptedLegal = false;
      _error = null;
    });
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

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why these images are required',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your assigned TODA reviews them to confirm identity, '
                        'driving eligibility, and vehicle registration before '
                        'you can carry passengers. Clear, current images also '
                        'support passenger safety and incident review. Access '
                        'is limited to you and authorised reviewers.',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Profile Photo
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Profile Photo',
                icon: Icons.person,
                file: _profilePhoto,
                instruction: 'Camera or gallery • square portrait',
                onTap: () => _pickImage(
                  setter: (file) => _profilePhoto = file,
                  aspectRatio: 1,
                  targetWidth: 1080,
                  allowGallery: true,
                ),
              ),

              if (_profilePhoto != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _profilePhoto, aspectRatio: 1),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Driver License Front
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Driver License (Front)',
                icon: Icons.badge_outlined,
                file: _licenseFront,
                instruction: 'Camera required • hold ID horizontally',
                cameraOnly: true,
                onTap: () => _pickImage(
                  setter: (file) => _licenseFront = file,
                  aspectRatio: 1.586,
                  targetWidth: 1600,
                  allowGallery: false,
                ),
              ),

              if (_licenseFront != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _licenseFront, aspectRatio: 1.586),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Driver License Back
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Driver License (Back)',
                icon: Icons.badge,
                file: _licenseBack,
                instruction: 'Camera required • hold ID horizontally',
                cameraOnly: true,
                onTap: () => _pickImage(
                  setter: (file) => _licenseBack = file,
                  aspectRatio: 1.586,
                  targetWidth: 1600,
                  allowGallery: false,
                ),
              ),

              if (_licenseBack != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _licenseBack, aspectRatio: 1.586),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Government ID
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Government ID',
                icon: Icons.credit_card,
                file: _governmentId,
                instruction: 'Camera required • hold ID horizontally',
                cameraOnly: true,
                onTap: () => _pickImage(
                  setter: (file) => _governmentId = file,
                  aspectRatio: 1.586,
                  targetWidth: 1600,
                  allowGallery: false,
                ),
              ),

              if (_governmentId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _governmentId, aspectRatio: 1.586),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Official Receipt (OR)
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Official Receipt (OR)',
                icon: Icons.receipt_long,
                file: _orDocument,
                instruction: 'Camera required • fill the document frame',
                cameraOnly: true,
                onTap: () => _pickImage(
                  setter: (file) => _orDocument = file,
                  aspectRatio: 1 / 1.414,
                  targetWidth: 1400,
                  allowGallery: false,
                ),
              ),

              if (_orDocument != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _orDocument, aspectRatio: 1 / 1.414),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Certificate of Registration (CR)
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Certificate of Registration (CR)',
                icon: Icons.description,
                file: _crDocument,
                instruction: 'Camera required • fill the document frame',
                cameraOnly: true,
                onTap: () => _pickImage(
                  setter: (file) => _crDocument = file,
                  aspectRatio: 1 / 1.414,
                  targetWidth: 1400,
                  allowGallery: false,
                ),
              ),

              if (_crDocument != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _crDocument, aspectRatio: 1 / 1.414),
              ],

              const SizedBox(height: AppSpacing.lg),

              //--------------------------------------------------
              // Vehicle Photo
              //--------------------------------------------------
              DocumentPickerCard(
                title: 'Vehicle Photo',
                icon: Icons.directions_car,
                file: _vehiclePhoto,
                instruction: 'Camera or gallery • show the full vehicle',
                onTap: () => _pickImage(
                  setter: (file) => _vehiclePhoto = file,
                  aspectRatio: 4 / 3,
                  targetWidth: 1600,
                  allowGallery: true,
                ),
              ),

              if (_vehiclePhoto != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ImagePreview(file: _vehiclePhoto, aspectRatio: 4 / 3),
              ],

              const SizedBox(height: AppSpacing.xl),

              LegalConsentCard(
                termsViewed: _termsViewed,
                privacyViewed: _privacyViewed,
                accepted: _acceptedLegal,
                onOpenTerms: () => _openLegalDocument(
                  route: AppRoutes.termsAndConditions,
                  terms: true,
                ),
                onOpenPrivacy: () => _openLegalDocument(
                  route: AppRoutes.privacyPolicy,
                  terms: false,
                ),
                onAcceptedChanged: (value) {
                  setState(() => _acceptedLegal = value);
                },
              ),

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
                    : 'Submitting sends these images to your assigned TODA for '
                          'verification. Registration is not approval to drive.',
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

String _prepareRegistrationImage(
  String sourcePath,
  double targetAspectRatio,
  int targetWidth,
) {
  final source = File(sourcePath);
  final decoded = image_lib.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    throw const FormatException('The selected file is not a readable image.');
  }

  var prepared = image_lib.bakeOrientation(decoded);
  final currentRatio = prepared.width / prepared.height;
  if ((currentRatio - targetAspectRatio).abs() > 0.01) {
    if (currentRatio > targetAspectRatio) {
      final cropWidth = (prepared.height * targetAspectRatio).round();
      prepared = image_lib.copyCrop(
        prepared,
        x: (prepared.width - cropWidth) ~/ 2,
        y: 0,
        width: cropWidth,
        height: prepared.height,
      );
    } else {
      final cropHeight = (prepared.width / targetAspectRatio).round();
      prepared = image_lib.copyCrop(
        prepared,
        x: 0,
        y: (prepared.height - cropHeight) ~/ 2,
        width: prepared.width,
        height: cropHeight,
      );
    }
  }

  if (prepared.width > targetWidth) {
    prepared = image_lib.copyResize(prepared, width: targetWidth);
  }

  var encoded = image_lib.encodeJpg(prepared, quality: 78);
  if (encoded.length > 3 * 1024 * 1024 && prepared.width > 1000) {
    prepared = image_lib.copyResize(prepared, width: 1000);
    encoded = image_lib.encodeJpg(prepared, quality: 72);
  }

  final output = File('$sourcePath.voltrike.jpg');
  output.writeAsBytesSync(encoded, flush: true);
  return output.path;
}
