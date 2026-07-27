import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/app_user.dart';
import '../models/driver.dart';
import '../models/passenger.dart';
import '../models/vehicle.dart';

/// Commits the Firestore records created during account registration.
///
/// Keeping these writes in one batch prevents an account from ending up with
/// only some of its required profile documents.
class RegistrationRepository {
  RegistrationRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> passengerRegistrationExists(String uid) async {
    final snapshot = await _firestore
        .collection(FirestoreConstants.passengers)
        .doc(uid)
        .get();
    return snapshot.exists;
  }

  Future<bool> driverRegistrationExists(String uid) async {
    final snapshot = await _firestore
        .collection(FirestoreConstants.drivers)
        .doc(uid)
        .get();
    return snapshot.exists;
  }

  Future<void> createPassengerRegistration({
    required AppUser user,
    required Passenger passenger,
  }) {
    final batch = _firestore.batch();

    batch.set(
      _firestore.collection(FirestoreConstants.users).doc(user.uid),
      user.toMap(),
    );
    batch.set(
      _firestore.collection(FirestoreConstants.passengers).doc(passenger.uid),
      passenger.toMap(),
    );

    return batch.commit();
  }

  Future<void> createDriverRegistration({
    required AppUser user,
    required Driver driver,
    required Vehicle vehicle,
  }) {
    final batch = _firestore.batch();

    batch.set(
      _firestore.collection(FirestoreConstants.users).doc(user.uid),
      user.toMap(),
    );
    batch.set(
      _firestore.collection(FirestoreConstants.vehicles).doc(vehicle.id),
      vehicle.toMap(),
    );
    batch.set(
      _firestore.collection(FirestoreConstants.drivers).doc(driver.uid),
      driver.toMap(),
    );

    return batch.commit();
  }
}
