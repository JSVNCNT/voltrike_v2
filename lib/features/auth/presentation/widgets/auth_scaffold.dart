import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.backgroundColor = AppColors.background,
    this.useSurface = true,
    this.maxWidth = AppConstants.maxContentWidth,
  });

  final Widget child;
  final Color backgroundColor;
  final bool useSurface;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          if (useSurface)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 176,
              child: ColoredBox(color: AppColors.primaryDark),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: useSurface
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                            child: child,
                          ),
                        )
                      : child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
