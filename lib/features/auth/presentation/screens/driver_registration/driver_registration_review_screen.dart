import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/errors/domain_error_mapper.dart';
import '../../../../../core/services/psgc_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';
import '../../../../../data/models/driver_registration_data.dart';
import '../../../../common/presentation/screens/legal/legal_document_versions.dart';
import '../../../services/driver_registration_review_policy.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_registration_data_provider.dart';
import '../../providers/driver_registration_provider.dart';
import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/legal_consent_card.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/registration_back_scope.dart';
import '../../widgets/registration_step_indicator.dart';
import '../../widgets/validation_message.dart';

class DriverRegistrationReviewScreen extends ConsumerStatefulWidget {
  const DriverRegistrationReviewScreen({super.key});

  @override
  ConsumerState<DriverRegistrationReviewScreen> createState() =>
      _DriverRegistrationReviewScreenState();
}

class _DriverRegistrationReviewScreenState
    extends ConsumerState<DriverRegistrationReviewScreen> {
  final PSGCService _locationService = PSGCService();

  String? _error;
  String? _regionName;
  String? _provinceName;
  String? _cityName;
  String? _barangayName;
  String? _todaName;
  bool _loadingLabels = true;
  bool _termsViewed = false;
  bool _privacyViewed = false;
  bool _acceptedLegal = false;

  @override
  void initState() {
    super.initState();
    final registration = ref.read(driverRegistrationDataProvider);
    _termsViewed = registration.termsVersion == LegalDocumentVersions.terms;
    _privacyViewed =
        registration.privacyVersion == LegalDocumentVersions.privacy;
    _loadReviewLabels();
  }

  Future<void> _loadReviewLabels() async {
    final registration = ref.read(driverRegistrationDataProvider);
    try {
      await _locationService.initialize();
      final toda = registration.todaId.isEmpty
          ? null
          : await ref.read(todaRepositoryProvider).getToda(registration.todaId);
      if (!mounted) return;
      setState(() {
        _regionName =
            _locationService.getRegionName(registration.region ?? '') ??
            registration.region;
        _provinceName =
            _locationService.getProvinceName(registration.province ?? '') ??
            registration.province;
        _cityName =
            _locationService.getCityName(registration.city ?? '') ??
            registration.city;
        _barangayName =
            _locationService.getBarangayName(registration.barangay ?? '') ??
            registration.barangay;
        _todaName = toda?.name ?? registration.todaId;
        _loadingLabels = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _regionName = registration.region;
        _provinceName = registration.province;
        _cityName = registration.city;
        _barangayName = registration.barangay;
        _todaName = registration.todaId;
        _loadingLabels = false;
      });
    }
  }

  Future<void> _openLegalDocument({
    required String route,
    required bool terms,
  }) async {
    final confirmed = await context.push<bool>('$route?acknowledge=true');
    if (!mounted || confirmed != true) return;

    ref
        .read(driverRegistrationDataProvider.notifier)
        .updateData(
          termsVersion: terms ? LegalDocumentVersions.terms : null,
          privacyVersion: terms ? null : LegalDocumentVersions.privacy,
        );
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

  void _edit(DriverRegistrationReviewSection section) {
    setState(() => _acceptedLegal = false);
    final route = switch (section) {
      DriverRegistrationReviewSection.personal => AppRoutes.driverRegisterStep1,
      DriverRegistrationReviewSection.assignment =>
        AppRoutes.driverRegisterStep2,
      DriverRegistrationReviewSection.vehicle => AppRoutes.driverRegisterStep3,
      DriverRegistrationReviewSection.documents => AppRoutes.uploadDocuments,
    };
    context.go('$route?returnToReview=true');
  }

  Future<void> _submit() async {
    final registration = ref.read(driverRegistrationDataProvider);
    final issue = DriverRegistrationReviewPolicy.firstIssue(registration);
    if (issue != null) {
      setState(() {
        _error = '${issue.message} Use Edit to correct that section.';
        _acceptedLegal = false;
      });
      return;
    }
    if (!_termsViewed || !_privacyViewed || !_acceptedLegal) {
      setState(() {
        _error =
            'Open the Terms and Conditions and Privacy Policy, then confirm '
            'your agreement before submitting.';
      });
      return;
    }

    setState(() => _error = null);
    final acceptedAt = DateTime.now();
    final submission = registration.copyWith(
      termsAcceptedAt: acceptedAt,
      privacyAcceptedAt: acceptedAt,
      termsVersion: LegalDocumentVersions.terms,
      privacyVersion: LegalDocumentVersions.privacy,
    );

    try {
      await ref
          .read(driverRegistrationControllerProvider.notifier)
          .register(submission);
      if (!mounted) return;
      ref.read(driverRegistrationDataProvider.notifier).clear();
      context.go(AppRoutes.driverUnderReview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = DomainErrorMapper.message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(driverRegistrationDataProvider);
    final submissionState = ref.watch(driverRegistrationControllerProvider);

    return RegistrationBackScope(
      fallbackRoute: AppRoutes.uploadDocuments,
      child: LoadingOverlay(
        isLoading: submissionState.isLoading,
        message: 'Submitting your application and images…',
        child: AuthScaffold(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthLogo(logoSize: 72),
              const SizedBox(height: AppSpacing.xl),
              const AuthHeader(
                title: 'Review your application',
                subtitle: 'Check every detail before submitting',
              ),
              const SizedBox(height: AppSpacing.lg),
              const RegistrationStepIndicator(currentStep: 5, totalSteps: 5),
              const SizedBox(height: AppSpacing.lg),
              const ValidationMessage(
                type: ValidationType.info,
                message:
                    'Nothing is submitted until you press Submit for TODA '
                    'Review. Your assigned TODA will verify these details and '
                    'images before deciding whether to approve the account.',
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                ValidationMessage(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              _ReviewSection(
                title: 'Personal and account information',
                icon: Icons.person_outline,
                editKey: const Key('edit-driver-personal'),
                onEdit: () => _edit(DriverRegistrationReviewSection.personal),
                children: [
                  _DetailRow(label: 'Full name', value: registration.fullName),
                  _DetailRow(
                    label: 'Date of birth',
                    value: _formatDate(registration.dateOfBirth),
                  ),
                  _DetailRow(label: 'Phone', value: registration.phoneNumber),
                  _DetailRow(label: 'Email', value: registration.email),
                  const _DetailRow(
                    label: 'Password',
                    value: 'Set securely • not displayed',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ReviewSection(
                title: 'Address and TODA assignment',
                icon: Icons.location_on_outlined,
                editKey: const Key('edit-driver-assignment'),
                onEdit: () => _edit(DriverRegistrationReviewSection.assignment),
                children: [
                  _DetailRow(
                    label: 'Region',
                    value: _loadingLabels ? 'Loading…' : _regionName,
                  ),
                  _DetailRow(
                    label: 'Province',
                    value: _loadingLabels ? 'Loading…' : _provinceName,
                  ),
                  _DetailRow(
                    label: 'City',
                    value: _loadingLabels ? 'Loading…' : _cityName,
                  ),
                  _DetailRow(
                    label: 'Barangay',
                    value: _loadingLabels ? 'Loading…' : _barangayName,
                  ),
                  _DetailRow(
                    label: 'TODA',
                    value: _loadingLabels ? 'Loading…' : _todaName,
                  ),
                  if (registration.licenseNumber.trim().isNotEmpty)
                    _DetailRow(
                      label: 'Licence no.',
                      value: _maskedIdentifier(registration.licenseNumber),
                    ),
                  if (registration.licenseExpiry != null)
                    _DetailRow(
                      label: 'Licence expiry',
                      value: _formatDate(registration.licenseExpiry),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ReviewSection(
                title: 'Vehicle information',
                icon: Icons.electric_rickshaw_outlined,
                editKey: const Key('edit-driver-vehicle'),
                onEdit: () => _edit(DriverRegistrationReviewSection.vehicle),
                children: [
                  _DetailRow(
                    label: 'Vehicle type',
                    value: registration.vehicleType,
                  ),
                  _DetailRow(
                    label: 'Plate number',
                    value: registration.plateNumber,
                  ),
                  _DetailRow(label: 'Brand', value: registration.vehicleBrand),
                  _DetailRow(label: 'Model', value: registration.vehicleModel),
                  _DetailRow(label: 'Color', value: registration.vehicleColor),
                  _DetailRow(
                    label: 'Passenger limit',
                    value: '${registration.seatingCapacity} seats',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ReviewSection(
                title: 'Registration images',
                icon: Icons.photo_library_outlined,
                editKey: const Key('edit-driver-documents'),
                onEdit: () => _edit(DriverRegistrationReviewSection.documents),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'Tap Edit to replace an unclear or incorrect image.',
                    ),
                  ),
                  _DocumentReviewGrid(registration: registration),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const ValidationMessage(
                type: ValidationType.info,
                message:
                    'Why submit? TODA reviewers need this information to confirm '
                    'your identity, age eligibility, vehicle registration, and '
                    'passenger capacity. Submission is an application—not '
                    'permission to start accepting rides.',
              ),
              const SizedBox(height: AppSpacing.lg),
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
                  setState(() {
                    _acceptedLegal = value;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                text: 'Submit for TODA Review',
                icon: Icons.send_outlined,
                onPressed: _submit,
                isLoading: submissionState.isLoading,
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: submissionState.isLoading
                    ? null
                    : () => context.go(AppRoutes.uploadDocuments),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to documents'),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.editKey,
    required this.onEdit,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Key editKey;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: editKey,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim().isNotEmpty == true ? value! : 'Not set';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentReviewGrid extends StatelessWidget {
  const _DocumentReviewGrid({required this.registration});

  final DriverRegistrationData registration;

  @override
  Widget build(BuildContext context) {
    final documents = <({String label, String? path, double ratio})>[
      (label: 'Profile photo', path: registration.profilePhoto, ratio: 1),
      (
        label: 'Licence front',
        path: registration.driverLicenseFront,
        ratio: 1.586,
      ),
      (
        label: 'Licence back',
        path: registration.driverLicenseBack,
        ratio: 1.586,
      ),
      (label: 'Government ID', path: registration.governmentId, ratio: 1.586),
      (label: 'Official Receipt', path: registration.orDocument, ratio: 0.707),
      (
        label: 'Certificate of Registration',
        path: registration.crDocument,
        ratio: 0.707,
      ),
      (label: 'Vehicle photo', path: registration.vehiclePhoto, ratio: 4 / 3),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 300;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final document in documents)
              SizedBox(
                width: itemWidth,
                child: _DocumentReviewTile(
                  label: document.label,
                  path: document.path,
                  aspectRatio: document.ratio,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DocumentReviewTile extends StatelessWidget {
  const _DocumentReviewTile({
    required this.label,
    required this.path,
    required this.aspectRatio,
  });

  final String label;
  final String? path;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final file = path == null || path!.isEmpty ? null : File(path!);
    final ready = file != null && file.existsSync() && file.lengthSync() > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: ready
                    ? Image.file(
                        file,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _MissingImage(),
                      )
                    : const _MissingImage(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingImage extends StatelessWidget {
  const _MissingImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.primaryContainer,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.error),
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Not set';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _maskedIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 4) return trimmed;
  return '•••• ${trimmed.substring(trimmed.length - 4)}';
}
