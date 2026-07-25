import 'dart:io';

import '../../core/constants/firestore_constants.dart';
import '../models/driver.dart';
import '../services/firestore_service.dart';
import 'storage_repository.dart';

class DriverRepository {
  DriverRepository({
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
  // Create Driver
  //==========================================================================

  Future<void> createDriver(
    Driver driver,
  ) {
    return _firestoreService.setDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  //==========================================================================
  // Update Driver
  //==========================================================================

  Future<void> updateDriver(
    Driver driver,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  //==========================================================================
  // Delete Driver
  //==========================================================================

  Future<void> deleteDriver(
    String uid,
  ) {
    return _firestoreService.deleteDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
    );
  }

  //==========================================================================
  // Get Driver
  //==========================================================================

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

  //==========================================================================
  // Driver Stream
  //==========================================================================

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

  //==========================================================================
  // Driver Online / Offline
  //==========================================================================

  Future<void> goOnline(
    String uid,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'isOnline': true,
        'isAvailable': true,
      },
    );
  }

  Future<void> goOffline(
    String uid,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'isOnline': false,
        'isAvailable': false,
        'currentBookingId': null,
      },
    );
  }

  //==========================================================================
  // Booking Availability
  //==========================================================================

  Future<void> setAvailable({
    required String uid,
    required bool available,
  }) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'isAvailable': available,
      },
    );
  }

  Future<void> assignBooking({
    required String uid,
    required String bookingId,
  }) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'currentBookingId': bookingId,
        'isAvailable': false,
      },
    );
  }

  Future<void> clearBooking(
    String uid,
  ) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'currentBookingId': null,
        'isAvailable': true,
      },
    );
  }

  //==========================================================================
  // Driver Live Location
  //==========================================================================

  Future<void> updateLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
      data: {
        'currentLatitude': latitude,
        'currentLongitude': longitude,
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
      path: 'drivers/$uid/profile.jpg',
      file: image,
    );
  }
}
