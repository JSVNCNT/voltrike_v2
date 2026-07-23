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
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (text.isNotEmpty)
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: textColor,
            ),
          ),

        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
            ),
            minimumSize: Size.zero,
            tapTargetSize:
                MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            actionText,
            textAlign: TextAlign.center,
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