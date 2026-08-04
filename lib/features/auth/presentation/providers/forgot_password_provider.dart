import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../controllers/forgot_password_controller.dart';
import 'auth_provider.dart';

final forgotPasswordControllerProvider =
    StateNotifierProvider<ForgotPasswordController, AsyncValue<void>>(
  (ref) {
    return ForgotPasswordController(
      authRepository: ref.read(authRepositoryProvider),
    );
  },
);