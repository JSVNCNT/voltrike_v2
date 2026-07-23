import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/repositories/driver_repository.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final userRepositoryProvider =
    Provider<UserRepository>((ref) {
  return UserRepository();
});

final driverRepositoryProvider =
    Provider<DriverRepository>((ref) {
  return DriverRepository();
});