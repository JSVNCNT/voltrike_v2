import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/app_user.dart';
import '../controllers/login_controller.dart';
import 'auth_provider.dart';

final loginControllerProvider =
    StateNotifierProvider<LoginController, AsyncValue<AppUser?>>(
  (ref) {
    return LoginController(
      authRepository: ref.read(authRepositoryProvider),
      userRepository: ref.read(userRepositoryProvider),
    );
  },
);