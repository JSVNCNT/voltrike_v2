import 'dart:io';

import '../../core/constants/firestore_constants.dart';
import '../models/passenger.dart';
import '../services/firestore_service.dart';
import 'storage_repository.dart';

class PassengerRepository {
  PassengerRepository({
    FirestoreService? firestoreService,
    StorageRepository? storageRepository,
  }) : _firestoreService = firestoreService ?? FirestoreService.instance,
       _storageRepository = storageRepository ?? StorageRepository();

  final FirestoreService _firestoreService;

  final StorageRepository _storageRepository;

  //==========================================================================
  // Create Passenger
  //==========================================================================

  Future<void> createPassenger(Passenger passenger) {
    throw UnsupportedError(
      'Passenger creation is owned by Go registration authority.',
    );
  }

  //==========================================================================
  // Update Passenger
  //==========================================================================

  Future<void> updatePassenger(Passenger passenger) {
    throw UnsupportedError('Passenger mutations are owned by Go authority.');
  }

  //==========================================================================
  // Delete Passenger
  //==========================================================================

  Future<void> deletePassenger(String uid) {
    throw UnsupportedError('Passenger records are retained by Go authority.');
  }

  //==========================================================================
  // Get Passenger
  //==========================================================================

  Future<Passenger?> getPassenger(String uid) async {
    final snapshot = await _firestoreService.getDocument(
      FirestoreConstants.passengers,
      uid,
    );

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return Passenger.fromMap(data);
  }

  //==========================================================================
  // Passenger Stream
  //==========================================================================

  Stream<Passenger?> passengerStream(String uid) {
    return _firestoreService
        .documentStream(FirestoreConstants.passengers, uid)
        .map((snapshot) {
          if (!snapshot.exists) {
            return null;
          }

          final data = snapshot.data();

          if (data == null) {
            return null;
          }

          return Passenger.fromMap(data);
        });
  }

  //==========================================================================
  // Upload Profile Photo
  //==========================================================================

  Future<String> uploadProfilePhoto({
    required String uid,
    required File image,
  }) {
    return _storageRepository.uploadFile(
      path: 'passengers/$uid/profile.jpg',
      file: image,
    );
  }
}
