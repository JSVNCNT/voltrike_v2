import '../../core/constants/firestore_constants.dart';
import '../models/driver.dart';
import '../services/firestore_service.dart';

class DriverRepository {
  DriverRepository({
    FirestoreService? firestoreService,
  }) : _firestoreService =
            firestoreService ??
            FirestoreService.instance;

  final FirestoreService _firestoreService;

  /// Create Driver
  Future<void> createDriver(
    Driver driver,
  ) {
    return _firestoreService.setDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  /// Update Driver
  Future<void> updateDriver(
    Driver driver,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  /// Delete Driver
  Future<void> deleteDriver(
    String uid,
  ) {
    return _firestoreService.deleteDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
    );
  }

  /// Get Driver
  Future<Driver?> getDriver(
    String uid,
  ) async {
    final snapshot =
        await _firestoreService.getDocument(
      FirestoreConstants.drivers,
      uid,
    );

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return Driver.fromMap(data);
  }

  /// Driver Stream
  Stream<Driver?> driverStream(
    String uid,
  ) {
    return _firestoreService
        .documentStream(
          FirestoreConstants.drivers,
          uid,
        )
        .map(
      (snapshot) {
        if (!snapshot.exists) {
          return null;
        }

        final data = snapshot.data();

        if (data == null) {
          return null;
        }

        return Driver.fromMap(data);
      },
    );
  }
}