import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

enum ValidationType {
  error,
  success,
  warning,
  info,
}

class ValidationMessage extends StatelessWidget {
  const ValidationMessage({
    super.key,
    required this.message,
    this.type = ValidationType.error,
  });

  final String message;
  final ValidationType type;

  Color get _color {
    switch (type) {
      case ValidationType.success:
        return AppColors.success;
      case ValidationType.warning:
        return AppColors.warning;
      case ValidationType.info:
        return AppColors.info;
      case ValidationType.error:
        return AppColors.error;
    }
  }

  IconData get _icon {
    switch (type) {
      case ValidationType.success:
        return Icons.check_circle;
      case ValidationType.warning:
        return Icons.warning_amber_rounded;
      case ValidationType.info:
        return Icons.info_outline;
      case ValidationType.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            _icon,
            color: _color,
          ),

          const SizedBox(width: AppSpacing.sm),

          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: _color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}