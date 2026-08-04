import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../controllers/email_verification_controller.dart';
import 'auth_provider.dart';

final emailVerificationControllerProvider =
    StateNotifierProvider<
        EmailVerificationController,
        AsyncValue<bool>>(
  (ref) {
    return EmailVerificationController(
      authRepository: ref.read(authRepositoryProvider),
    );
  },
);