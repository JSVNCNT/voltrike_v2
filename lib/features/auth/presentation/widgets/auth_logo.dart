import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class AuthLogo extends StatelessWidget {
  const AuthLogo({
    super.key,
    this.logoSize = 84,
    this.textColor = AppColors.textPrimary,
    this.taglineColor = AppColors.textSecondary,
  });

  final double logoSize;
  final Color textColor;
  final Color taglineColor;

  @override
  Widget build(BuildContext context) {
    final useLightLogo = textColor.computeLuminance() > 0.5;

    return Column(
      children: [
        Image.asset(
          useLightLogo ? AppAssets.logoLight : AppAssets.logoDark,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
        ),

        const SizedBox(height: 16),

        Text(
          AppStrings.appName,
          style: AppTextStyles.headlineMedium.copyWith(
            color: textColor,
            letterSpacing: 1.2,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          AppStrings.appTagline,
          style: AppTextStyles.bodyMedium.copyWith(
            color: taglineColor,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}
