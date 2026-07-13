import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({
    super.key,
    required this.file,
    this.height = 180,
  });

  final File? file;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(
            AppRadius.lg,
          ),
          border: Border.all(
            color: Colors.grey.shade300,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.image_outlined,
            size: 56,
            color: Colors.grey,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(
                AppSpacing.md,
              ),
              child: Stack(
                children: [
                  InteractiveViewer(
                    child: Image.file(
                      file!,
                      fit: BoxFit.contain,
                    ),
                  ),

                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          AppRadius.lg,
        ),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: height,
              child: Image.file(
                file!,
                fit: BoxFit.cover,
              ),
            ),

            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}