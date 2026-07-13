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
  });

  final String title;
  final IconData icon;
  final File? file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          AppRadius.lg,
        ),
        side: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(
          AppRadius.lg,
        ),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius: BorderRadius.circular(
                    AppRadius.md,
                  ),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(
                width: AppSpacing.md,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          AppTextStyles.titleMedium,
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      file == null
                          ? 'Tap to upload'
                          : 'Selected',
                      style:
                          AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),

              file != null
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    )
                  : const Icon(
                      Icons.upload_file,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}