import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

class FixedLightTheme extends StatelessWidget {
  const FixedLightTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.lightSystemUiOverlayStyle,
        child: child,
      ),
    );
  }
}
