import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.compact = false,
  });

  final bool isLoading;
  final Widget child;
  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,

        if (isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black45,
              child: Center(
                child: compact
                    ? Semantics(
                        label: message ?? 'Loading',
                        liveRegion: true,
                        child: Container(
                          key: const Key('compact-loading-indicator'),
                          width: 56,
                          height: 56,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: AppColors.primary,
                            ),

                            if (message != null) ...[
                              const SizedBox(height: 18),

                              Text(message!),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
