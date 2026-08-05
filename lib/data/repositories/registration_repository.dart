import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_constants.dart';
import '../../core/services/voltrike_api.dart';
import '../models/app_user.dart';
import '../models/driver.dart';
import '../models/passenger.dart';
import '../models/vehicle.dart';

/// Commits the Firestore records created during account registration.
///
/// Keeping these writes in one batch prevents an account from ending up with
/// only some of its required profile documents.
class RegistrationRepository {
  RegistrationRepository({FirebaseFirestore? firestore, VoltrikeApi? api})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _api = api ?? VoltrikeApi.instance;

  final FirebaseFirestore _firestore;
  final VoltrikeApi _api;

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
  }) async {
    await _api.operation('createPassengerRegistration', {
      'user': user.toMap(),
      'passenger': passenger.toMap(),
    });
  }

  Future<void> createDriverRegistration({
    required AppUser user,
    required Driver driver,
    required Vehicle vehicle,
  }) async {
    await _api.operation('createDriverRegistration', {
      'user': user.toMap(),
      'driver': driver.toMap(),
      'vehicle': vehicle.toMap(),
    });
  }
}
