import 'package:flutter/material.dart';

class SnackbarService {
  const SnackbarService._();

  static void showSuccess(
    BuildContext context,
    String message,
  ) {
    _show(
      context,
      message,
      Colors.green,
      Icons.check_circle_outline_rounded,
    );
  }

  static void showError(
    BuildContext context,
    String message,
  ) {
    _show(
      context,
      message,
      Colors.red,
      Icons.error_outline_rounded,
    );
  }

  static void showInfo(
    BuildContext context,
    String message,
  ) {
    _show(
      context,
      message,
      Colors.blue,
      Icons.info_outline_rounded,
    );
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
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
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
        ),
      );
  }
}