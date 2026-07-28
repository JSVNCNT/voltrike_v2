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
  });

  final String title;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;
  final String instruction;
  final bool cameraOnly;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, ${file == null ? 'not selected' : 'selected'}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),

                const SizedBox(width: AppSpacing.md),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleMedium),

                      const SizedBox(height: 4),

                      Text(
                        file == null
                            ? instruction
                            : file!.path.split(Platform.pathSeparator).last,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ],
                  ),
                ),

                file != null
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : Icon(
                        cameraOnly
                            ? Icons.photo_camera_outlined
                            : Icons.add_photo_alternate_outlined,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
