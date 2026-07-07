class Validators {
  const Validators._();

  // ===========================================================================
  // Required Field
  // ===========================================================================

  static String? requiredField(
    String? value, {
    String fieldName = 'This field',
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  // ===========================================================================
  // Email
  // ===========================================================================

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }

    final emailRegex = RegExp(
      r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$',
    );

    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  // ===========================================================================
  // Phone Number (Philippines)
  // ===========================================================================

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required.';
    }

    final phoneRegex = RegExp(r'^(09|\+639)\d{9}$');

    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Enter a valid Philippine mobile number.';
    }

    return null;
  }

  // ===========================================================================
  // Password
  // ===========================================================================

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required.';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    return null;
  }

  // ===========================================================================
  // Confirm Password
  // ===========================================================================

  static String? confirmPassword(
    String? password,
    String? confirmPassword,
  ) {
    if (confirmPassword == null || confirmPassword.isEmpty) {
      return 'Please confirm your password.';
    }

    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }

    return null;
  }

  // ===========================================================================
  // OTP
  // ===========================================================================

  static String? otp(String? value) {
    if (value == null || value.length != 6) {
      return 'Enter the 6-digit verification code.';
    }

    return null;
  }
}