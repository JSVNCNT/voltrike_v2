import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';

class ForgotPasswordController
    extends StateNotifier<AsyncValue<void>> {
  ForgotPasswordController({
    required AuthRepository authRepository,
  })  : _authRepository = authRepository,
        super(const AsyncData(null));

  final AuthRepository _authRepository;

  Future<void> sendResetEmail(
    String email,
  ) async {
    state = const AsyncLoading();

    try {
      await _authRepository.sendPasswordResetEmail(
        email,
      );

      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }
}