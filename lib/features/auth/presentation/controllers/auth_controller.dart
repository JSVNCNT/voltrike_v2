import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/user_repository.dart';

/// ---------------------------------------------------------------------------
/// Authentication
/// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

/// ---------------------------------------------------------------------------
/// Users
/// ---------------------------------------------------------------------------

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);

/// ---------------------------------------------------------------------------
/// Passengers
/// ---------------------------------------------------------------------------

final passengerRepositoryProvider =
    Provider<PassengerRepository>(
  (ref) => PassengerRepository(),
);