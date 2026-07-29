import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';

class SnackbarService {
  const SnackbarService._();

  static void showSuccess(BuildContext context, String message) {
    final colors = AppSemanticColors.of(context);
    _show(
      context,
      message,
      colors.success,
      colors.onSuccess,
      Icons.check_circle_outline_rounded,
    );
  }

  static void showError(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    _show(
      context,
      message,
      colorScheme.error,
      colorScheme.onError,
      Icons.error_outline_rounded,
    );
  }

  static void showInfo(BuildContext context, String message) {
    final colors = AppSemanticColors.of(context);
    _show(
      context,
      message,
      colors.info,
      colors.onInfo,
      Icons.info_outline_rounded,
    );
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
    Color onColor,
    IconData icon,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          content: Row(
            children: [
              Icon(icon, color: onColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: TextStyle(color: onColor)),
              ),
            ],
          ),
        ),
      );
  }
}
