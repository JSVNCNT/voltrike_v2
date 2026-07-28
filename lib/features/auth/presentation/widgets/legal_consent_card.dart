import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class LegalConsentCard extends StatelessWidget {
  const LegalConsentCard({
    super.key,
    required this.termsViewed,
    required this.privacyViewed,
    required this.accepted,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    required this.onAcceptedChanged,
  });

  final bool termsViewed;
  final bool privacyViewed;
  final bool accepted;
  final Future<void> Function() onOpenTerms;
  final Future<void> Function() onOpenPrivacy;
  final ValueChanged<bool> onAcceptedChanged;

  bool get canAccept => termsViewed && privacyViewed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review before you agree',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Open both documents. Your account will record the versions you '
              'accepted and the acceptance date.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _DocumentLink(
              label: 'Terms and Conditions',
              viewed: termsViewed,
              onTap: onOpenTerms,
            ),
            _DocumentLink(
              label: 'Privacy Policy',
              viewed: privacyViewed,
              onTap: onOpenPrivacy,
            ),
            const Divider(),
            CheckboxListTile(
              value: accepted,
              onChanged: canAccept
                  ? (value) => onAcceptedChanged(value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I have read and agree to the Terms and Conditions and '
                'acknowledge the Privacy Policy.',
              ),
              subtitle: canAccept
                  ? null
                  : const Text('Open and confirm both documents first.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentLink extends StatelessWidget {
  const _DocumentLink({
    required this.label,
    required this.viewed,
    required this.onTap,
  });

  final String label;
  final bool viewed;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        viewed ? Icons.check_circle_rounded : Icons.description_outlined,
        color: viewed ? AppColors.success : AppColors.primary,
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: onTap,
    );
  }
}
