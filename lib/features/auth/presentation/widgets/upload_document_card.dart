import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

class UploadDocumentCard extends StatelessWidget {
  const UploadDocumentCard({
    super.key,
    required this.title,
    required this.onTap,
    this.fileName,
    this.icon = Icons.upload_file_rounded,
  });

  final String title;
  final String? fileName;
  final IconData icon;
  final VoidCallback onTap;

  bool get hasFile =>
      fileName != null && fileName!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: hasFile
                    ? AppColors.success.withValues(alpha: .12)
                    : AppColors.primary.withValues(alpha: .10),
                child: Icon(
                  hasFile
                      ? Icons.check
                      : icon,
                  color: hasFile
                      ? AppColors.success
                      : AppColors.primary,
                ),
              ),

              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium,
                    ),

                    const SizedBox(height: 4),

                    Text(
                      hasFile
                          ? fileName!
                          : 'Tap to upload',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}