import 'package:flutter/material.dart';

import '../widgets/dialogs/confirmation_dialog.dart';
import '../widgets/dialogs/error_dialog.dart';
import '../widgets/dialogs/success_dialog.dart';

class DialogService {
  const DialogService._();

  static Future<void> showError(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ErrorDialog(
        title: title,
        message: message,
      ),
    );
  }

  static Future<void> showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Continue',
  }) {
    return showDialog(
      context: context,
      builder: (_) => SuccessDialog(
        title: title,
        message: message,
        buttonText: buttonText,
      ),
    );
  }

  static Future<void> showConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    required VoidCallback onConfirm,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        onConfirm: onConfirm,
      ),
    );
  }
}