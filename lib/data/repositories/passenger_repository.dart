import 'dart:io';

import '../../core/constants/firestore_constants.dart';
import '../models/passenger.dart';
import '../services/firestore_service.dart';
import 'storage_repository.dart';

class PassengerRepository {
  PassengerRepository({
    FirestoreService? firestoreService,
    StorageRepository? storageRepository,
  })  : _firestoreService =
            firestoreService ??
                FirestoreService.instance,
        _storageRepository =
            storageRepository ??
                StorageRepository();

  final FirestoreService _firestoreService;

  final StorageRepository _storageRepository;

  //==========================================================================
  // Create Passenger
  //==========================================================================

  Future<void> createPassenger(
    Passenger passenger,
  ) {
    return _firestoreService.setDocument(
      collection: FirestoreConstants.passengers,
      documentId: passenger.uid,
      data: passenger.toMap(),
    );
  }

  //==========================================================================
  // Update Passenger
  //==========================================================================

  Future<void> updatePassenger(
    Passenger passenger,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.passengers,
      documentId: passenger.uid,
      data: passenger.toMap(),
    );
  }

  //==========================================================================
  // Delete Passenger
  //==========================================================================

  Future<void> deletePassenger(
    String uid,
  ) {
    return _firestoreService.deleteDocument(
      collection: FirestoreConstants.passengers,
      documentId: uid,
    );
  }

  //==========================================================================
  // Get Passenger
  //==========================================================================

  Future<Passenger?> getPassenger(
    String uid,
  ) async {
    final snapshot =
        await _firestoreService.getDocument(
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

  Stream<Passenger?> passengerStream(
    String uid,
  ) {
    return _firestoreService
        .documentStream(
          FirestoreConstants.passengers,
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

        return Passenger.fromMap(data);
      },
    );
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
