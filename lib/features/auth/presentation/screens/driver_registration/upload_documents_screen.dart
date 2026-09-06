import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../services/registration_image_preparer.dart';

import '../../providers/driver_registration_data_provider.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/document_picker_card.dart';
import '../../widgets/image_preview.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/registration_back_scope.dart';
import '../../widgets/registration_step_indicator.dart';
import '../../widgets/validation_message.dart';

class UploadDocumentsScreen extends ConsumerStatefulWidget {
  const UploadDocumentsScreen({super.key, this.returnToReview = false});

  final bool returnToReview;

  @override
  ConsumerState<UploadDocumentsScreen> createState() =>
      _UploadDocumentsScreenState();
}

class _UploadDocumentsScreenState extends ConsumerState<UploadDocumentsScreen> {
  final ImagePicker _picker = ImagePicker();
  final RegistrationImagePreparer _imagePreparer =
      const RegistrationImagePreparer();

  File? _profilePhoto;

  File? _licenseFront;

  File? _licenseBack;

  File? _governmentId;

  File? _orDocument;

  File? _crDocument;

  File? _vehiclePhoto;

  String? _error;
  bool _isPickingImage = false;
  bool _isPreparing = false;

  @override
  void initState() {
    super.initState();
    final registration = ref.read(driverRegistrationDataProvider);
    _profilePhoto = _fileFromPath(registration.profilePhoto);
    _licenseFront = _fileFromPath(registration.driverLicenseFront);
    _licenseBack = _fileFromPath(registration.driverLicenseBack);
    _governmentId = _fileFromPath(registration.governmentId);
    _orDocument = _fileFromPath(registration.orDocument);
    _crDocument = _fileFromPath(registration.crDocument);
    _vehiclePhoto = _fileFromPath(registration.vehiclePhoto);
  }

  File? _fileFromPath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  Future<void> _pickImage({
    required void Function(File file) setter,
    required File? Function() currentFile,
    required double aspectRatio,
    required int targetWidth,
    required bool allowGallery,
  }) async {
    if (_isPickingImage || _isPreparing) return;
    setState(() {
      _isPickingImage = true;
      _error = null;
    });
    try {
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

      final picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 92,
        maxWidth: 2600,
        maxHeight: 2600,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _isPickingImage = false;
        _isPreparing = true;
      });
      final file = await _imagePreparer.prepare(
        sourcePath: picked.path,
        targetAspectRatio: aspectRatio,
        targetWidth: targetWidth,
      );
      if (!mounted) {
        await _deletePreparedImage(file);
        return;
      }
      final previous = currentFile();
      setState(() {
        setter(file);
        _error = null;
      });
      _persistDocuments();
      if (previous?.path != file.path) {
        await _deletePreparedImage(previous);
      }
    } catch (error, stackTrace) {
      debugPrint('Registration image preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = error is RegistrationImagePreparationException
            ? error.message
            : 'Could not prepare that image. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
          _isPreparing = false;
        });
      }
    }
  }

  Future<void> _deletePreparedImage(File? file) async {
    if (file == null || !file.path.endsWith('.voltrike.jpg')) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      debugPrint('An obsolete prepared registration image was not removed.');
    }
  }

  bool get _isComplete {
    return <File?>[
      _profilePhoto,
      _licenseFront,
      _licenseBack,
      _governmentId,
      _orDocument,
      _crDocument,
      _vehiclePhoto,
    ].every((file) => file != null && file.existsSync());
  }

  void _persistDocuments() {
    ref
        .read(driverRegistrationDataProvider.notifier)
        .updateData(
          profilePhoto: _profilePhoto?.path,
          driverLicenseFront: _licenseFront?.path,
          driverLicenseBack: _licenseBack?.path,
          governmentId: _governmentId?.path,
          orDocument: _orDocument?.path,
          crDocument: _crDocument?.path,
          vehiclePhoto: _vehiclePhoto?.path,
        );
  }

  void _continue() {
    if (!_isComplete) {
      setState(() {
        _error = 'Please capture all required registration images.';
      });
      return;
    }

    setState(() {
      _error = null;
    });
    _persistDocuments();
    context.go(AppRoutes.driverRegisterReview);
  }

  @override
  Widget build(BuildContext context) {
    return RegistrationBackScope(
      fallbackRoute: widget.returnToReview
          ? AppRoutes.driverRegisterReview
          : AppRoutes.driverRegisterStep3,
      child: LoadingOverlay(
        isLoading: _isPreparing,
        message: 'Preparing image',
        compact: true,
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
                const RegistrationStepIndicator(currentStep: 4, totalSteps: 5),
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
                  previewAspectRatio: 1,
                  placeholderText: 'Your portrait here',
                  instruction: 'Camera or gallery • square portrait',
                  onTap: () => _pickImage(
                    setter: (file) => _profilePhoto = file,
                    currentFile: () => _profilePhoto,
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
                  sampleAsset: 'assets/images/Driver_License_Front_Sample.png',
                  previewAspectRatio: 1.586,
                  instruction: 'Camera required • hold ID horizontally',
                  cameraOnly: true,
                  onTap: () => _pickImage(
                    setter: (file) => _licenseFront = file,
                    currentFile: () => _licenseFront,
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
                  sampleAsset: 'assets/images/Driver_License_Back_Sample.png',
                  previewAspectRatio: 1.586,
                  instruction: 'Camera required • hold ID horizontally',
                  cameraOnly: true,
                  onTap: () => _pickImage(
                    setter: (file) => _licenseBack = file,
                    currentFile: () => _licenseBack,
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
                  sampleAsset: 'assets/images/Government_ID_Sample.png',
                  previewAspectRatio: 1.586,
                  instruction: 'Camera required • hold ID horizontally',
                  cameraOnly: true,
                  onTap: () => _pickImage(
                    setter: (file) => _governmentId = file,
                    currentFile: () => _governmentId,
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
                  sampleAsset: 'assets/images/LTO_OR_SAMPLE.png',
                  previewAspectRatio: 1 / 1.414,
                  instruction: 'Camera required • fill the document frame',
                  cameraOnly: true,
                  onTap: () => _pickImage(
                    setter: (file) => _orDocument = file,
                    currentFile: () => _orDocument,
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
                  sampleAsset: 'assets/images/LTO_CR_SAMPLE.png',
                  previewAspectRatio: 1 / 1.414,
                  instruction: 'Camera required • fill the document frame',
                  cameraOnly: true,
                  onTap: () => _pickImage(
                    setter: (file) => _crDocument = file,
                    currentFile: () => _crDocument,
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
                  placeholderText: 'Your full vehicle here',
                  instruction: 'Camera or gallery • show the full vehicle',
                  onTap: () => _pickImage(
                    setter: (file) => _vehiclePhoto = file,
                    currentFile: () => _vehiclePhoto,
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

                //--------------------------------------------------
                // Continue to review
                //--------------------------------------------------
                PrimaryButton(
                  text: 'Continue to Review',
                  onPressed: _continue,
                  icon: Icons.fact_check_outlined,
                ),

                const SizedBox(height: AppSpacing.md),

                TextButton.icon(
                  onPressed: () {
                    _persistDocuments();
                    context.go(
                      widget.returnToReview
                          ? AppRoutes.driverRegisterReview
                          : AppRoutes.driverRegisterStep3,
                    );
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(
                    widget.returnToReview
                        ? 'Cancel and return to review'
                        : 'Back',
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                const Text(
                  'Your images are not submitted yet. Review every detail and '
                  'give final consent on the next screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
