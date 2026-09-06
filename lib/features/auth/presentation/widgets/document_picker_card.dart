import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

class DocumentPickerCard extends StatelessWidget {
  const DocumentPickerCard({
    super.key,
    required this.title,
    required this.icon,
    this.file,
    required this.onTap,
    this.instruction = 'Tap to add photo',
    this.cameraOnly = false,
    this.sampleAsset,
    this.previewAspectRatio = 4 / 3,
    this.placeholderText = 'Add a clear photo',
  });

  final String title;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  final String instruction;
  final bool cameraOnly;
  final String? sampleAsset;
  final double previewAspectRatio;
  final String placeholderText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title, ${file == null ? 'not selected' : 'selected'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(title, style: AppTextStyles.titleMedium),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (file != null)
                    const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(instruction, style: AppTextStyles.bodyMedium),
              if (file == null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: AspectRatio(
                    aspectRatio: previewAspectRatio,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: sampleAsset != null
                          ? Image.asset(
                              sampleAsset!,
                              fit: BoxFit.contain,
                              semanticLabel: '$title sample only',
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: 80,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    placeholderText,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  file!.path.split(Platform.pathSeparator).last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(
                  cameraOnly
                      ? Icons.photo_camera_outlined
                      : Icons.add_photo_alternate_outlined,
                ),
                label: Text(
                  file != null
                      ? 'Replace photo'
                      : cameraOnly
                      ? 'Take photo'
                      : 'Add photo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
