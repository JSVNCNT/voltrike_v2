import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/user_repository.dart';

class LoginController extends StateNotifier<AsyncValue<AppUser?>> {
  LoginController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        super(const AsyncData(null));

  final AuthRepository _authRepository;
  final UserRepository _userRepository;

  Future<AppUser?> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();

    try {
      await _authRepository.signIn(
        email: email,
        password: password,
      );

      final firebaseUser = _authRepository.currentUser;

      if (firebaseUser == null) {
        state = const AsyncData(null);
        return null;
      }

      final appUser =
          await _userRepository.getUser(firebaseUser.uid);

      state = AsyncData(appUser);

      return appUser;
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    state = const AsyncLoading();

    try {
      await _authRepository.signOut();
      state = const AsyncData(null);
    } catch (e, stackTrace) {
      state = AsyncError(e, stackTrace);
    }
  }

  Future<bool> reloadEmailVerification() async {
    await _authRepository.reloadUser();
    return _authRepository.isEmailVerified;
  }
}