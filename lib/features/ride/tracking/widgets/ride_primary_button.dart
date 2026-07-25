import 'package:flutter/material.dart';

import '../models/ride_action.dart';

/// ===========================================================================
/// Ride Primary Button
///
/// Displays the main ride action.
///
/// Shared by:
/// • Driver Booking Tracking Screen
/// • Passenger Booking Tracking Screen
/// ===========================================================================
class RidePrimaryButton extends StatelessWidget {
  const RidePrimaryButton({
    super.key,
    required this.action,
    required this.onPressed,
    this.isLoading = false,
    this.enabled = true,
  });

  final RidePrimaryAction action;

  final VoidCallback? onPressed;

  final bool isLoading;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (action == RidePrimaryAction.none) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: enabled && !isLoading
            ? onPressed
            : null,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : Icon(
                action.icon,
              ),
        label: Text(
          action.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}