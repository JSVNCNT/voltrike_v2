import '../../core/constants/firestore_constants.dart';
import '../models/app_user.dart';
import '../services/firestore_service.dart';

class UserRepository {
  UserRepository({
    FirestoreService? firestoreService,
  }) : _firestoreService =
            firestoreService ?? FirestoreService.instance;

  final FirestoreService _firestoreService;

  Future<void> createUser(
    AppUser user,
  ) {
    return _firestoreService.setDocument(
      collection: FirestoreConstants.users,
      documentId: user.uid,
      data: user.toMap(),
    );
  }

  Future<void> updateUser(
    AppUser user,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.users,
      documentId: user.uid,
      data: user.toMap(),
    );
  }

  Future<void> deleteUser(
    String uid,
  ) {
    return _firestoreService.deleteDocument(
      collection: FirestoreConstants.users,
      documentId: uid,
    );
  }

  Future<AppUser?> getUser(
    String uid,
  ) async {
    final snapshot =
        await _firestoreService.getDocument(
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

  Stream<AppUser?> userStream(
    String uid,
  ) {
    return _firestoreService
        .documentStream(
          FirestoreConstants.users,
          uid,
        )
        .map((snapshot) {
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