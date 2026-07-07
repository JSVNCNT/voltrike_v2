import 'package:flutter/material.dart';

import '../../utils/extensions.dart';

class ScreenPadding extends StatelessWidget {
  const ScreenPadding({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.horizontalPadding,
        vertical: context.verticalPadding,
      ),
      child: child,
    );
  }
}