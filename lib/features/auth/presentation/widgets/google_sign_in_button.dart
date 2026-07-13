import 'package:flutter/material.dart';

import '../../../../core/widgets/buttons/outlined_button.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedPrimaryButton(
      text: 'Continue with Google',
      icon: Icons.g_mobiledata,
      onPressed: onPressed,
    );
  }
}