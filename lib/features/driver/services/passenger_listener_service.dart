import '../../../data/models/app_user.dart';
import '../../../data/repositories/user_repository.dart';

/// ===========================================================================
/// Passenger Listener Service
///
/// Listens to the current booking passenger's profile.
///
/// Firestore
/// users/{passengerId}
/// ===========================================================================
class PassengerListenerService {
  PassengerListenerService._();

  static final PassengerListenerService instance =
      PassengerListenerService._();

  final UserRepository _userRepository =
      UserRepository();

  Stream<AppUser?> listen(
    String passengerId,
  ) {
    return _userRepository.userStream(
      passengerId,
    );
  }
}