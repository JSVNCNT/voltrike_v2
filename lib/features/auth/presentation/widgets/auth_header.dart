import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.titleColor = AppColors.textPrimary,
    this.subtitleColor = AppColors.textSecondary,
    this.textAlign = TextAlign.left,
  });

  final String title;
  final String subtitle;

  final Color titleColor;
  final Color subtitleColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: textAlign,
          style: AppTextStyles.titleLarge.copyWith(color: titleColor),
        ),

        const SizedBox(height: 7),

        Text(
          subtitle,
          textAlign: textAlign,
          style: AppTextStyles.bodyMedium.copyWith(color: subtitleColor),
        ),
      ],
    );
  }
}
