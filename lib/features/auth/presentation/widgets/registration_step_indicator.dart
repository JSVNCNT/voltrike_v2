import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class RegistrationStepIndicator extends StatelessWidget {
  const RegistrationStepIndicator({
    super.key,
    required this.currentStep,
    this.totalSteps = 3,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        totalSteps,
        (index) {
          final step = index + 1;
          final active = step <= currentStep;

          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor:
                      active ? AppColors.primary : AppColors.disabled,
                  child: Text(
                    '$step',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (step != totalSteps)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: active
                          ? AppColors.primary
                          : AppColors.disabled,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}