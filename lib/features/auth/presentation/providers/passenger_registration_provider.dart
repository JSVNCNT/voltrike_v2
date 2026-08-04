import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../controllers/passenger_registration_controller.dart';
import 'auth_provider.dart';

final passengerRegistrationControllerProvider =
    StateNotifierProvider<PassengerRegistrationController, AsyncValue<void>>((
      ref,
    ) {
      return PassengerRegistrationController(
        authRepository: ref.read(authRepositoryProvider),
        registrationRepository: ref.read(registrationRepositoryProvider),
      );
    });
