import '../../core/constants/firestore_constants.dart';
import '../models/app_user.dart';
import '../services/firestore_service.dart';
import '../../core/services/voltrike_api.dart';

class UserRepository {
  UserRepository({FirestoreService? firestoreService, VoltrikeApi? api})
    : _firestoreService = firestoreService ?? FirestoreService.instance,
      _api = api ?? VoltrikeApi.instance;

  final FirestoreService _firestoreService;
  final VoltrikeApi _api;

  //==========================================================================
  // Create User
  //==========================================================================

  Future<void> createUser(AppUser user) {
    throw UnsupportedError(
      'User creation is owned by Go registration authority.',
    );
  }

  //==========================================================================
  // Update User
  //==========================================================================

  Future<void> updateUser(AppUser user) {
    throw UnsupportedError('User profile mutations are owned by Go authority.');
  }

  //==========================================================================
  // Update Profile Image
  //==========================================================================

  Future<void> updateProfileImage({
    required String uid,
    required String photoUrl,
  }) {
    return _api
        .operation('updateMyProfileImage', {'photoUrl': photoUrl})
        .then((_) {});
  }

  //==========================================================================
  // Delete User
  //==========================================================================

  Future<void> deleteUser(String uid) {
    throw UnsupportedError('User records are retained by Go authority.');
  }

  //==========================================================================
  // Get User
  //==========================================================================

  Future<AppUser?> getUser(String uid) async {
    final snapshot = await _firestoreService.getDocument(
      FirestoreConstants.users,
      uid,
    );

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return AppUser.fromMap(data);
  }

  //==========================================================================
  // User Exists
  //==========================================================================

  Future<bool> userExists(String uid) async {
    final snapshot = await _firestoreService.getDocument(
      FirestoreConstants.users,
      uid,
    );

    return snapshot.exists;
  }

  //==========================================================================
  // User Stream
  //==========================================================================

  Stream<AppUser?> userStream(String uid) {
    return _firestoreService.documentStream(FirestoreConstants.users, uid).map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }

      final data = snapshot.data();

      if (data == null) {
        return null;
      }

      return AppUser.fromMap(data);
    });
  }
}
