import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../data/repositories/auth_repository.dart';

class EmailVerificationController extends StateNotifier<AsyncValue<bool>> {
  EmailVerificationController({required AuthRepository authRepository})
    : _authRepository = authRepository,
      super(const AsyncData(false));

  final AuthRepository _authRepository;

  /// Sends another verification email.
  Future<VerificationEmailDelivery> resendVerificationEmail() async {
    final previousVerified = state.value ?? false;

    state = const AsyncLoading();

    try {
      final delivery = await _authRepository.sendEmailVerification();

      // Keep the previous verification state.
      state = AsyncData(previousVerified);
      return delivery;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// Reloads the current Firebase user and checks
  /// whether the email has been verified.
  Future<bool> refreshVerification() async {
    state = const AsyncLoading();

    try {
      await _authRepository.reloadUser();

      final verified = _authRepository.isEmailVerified;

      state = AsyncData(verified);

      return verified;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  /// Returns the current verification state
  /// without contacting Firebase.
  bool get isVerified => state.value ?? false;
}
