import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.text,
    required this.actionText,
    required this.onPressed,
    this.textColor = AppColors.textSecondary,
    this.actionColor = AppColors.primary,
  });

  final String text;
  final String actionText;
  final VoidCallback onPressed;

  final Color textColor;
  final Color actionColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(
            color: textColor,
          ),
        ),

        TextButton(
          onPressed: onPressed,
          child: Text(
            actionText,
            style: AppTextStyles.bodyMedium.copyWith(
              color: actionColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}