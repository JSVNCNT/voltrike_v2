import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_semantic_colors.dart';
import '../buttons/primary_button.dart';

class SuccessDialog extends StatelessWidget {
  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.buttonText = 'Continue',
  });

  final String title;
  final String message;
  final String buttonText;

  @override
  Widget build(BuildContext context) {
    final semanticColors = AppSemanticColors.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: semanticColors.successContainer,
              child: Icon(
                Icons.check_circle_outline_rounded,
                color: semanticColors.onSuccessContainer,
                size: 34,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),

            const SizedBox(height: 12),

            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            const SizedBox(height: 24),

            PrimaryButton(
              text: buttonText,
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
