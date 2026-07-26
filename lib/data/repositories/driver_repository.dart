import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/driver.dart';
import '../services/firestore_service.dart';
import 'storage_repository.dart';

class DriverRepository {
  DriverRepository({
    FirestoreService? firestoreService,
    StorageRepository? storageRepository,
    FirebaseFunctions? functions,
  }) : _firestoreService = firestoreService ?? FirestoreService.instance,
       _storageRepository = storageRepository ?? StorageRepository(),
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirestoreService _firestoreService;

  final StorageRepository _storageRepository;
  final FirebaseFunctions _functions;

  //==========================================================================
  // Create Driver
  //==========================================================================

  Future<void> createDriver(Driver driver) {
    return _firestoreService.setDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  //==========================================================================
  // Update Driver
  //==========================================================================

  Future<void> updateDriver(Driver driver) {
    return _firestoreService.updateDocument(
      collection: FirestoreConstants.drivers,
      documentId: driver.uid,
      data: driver.toMap(),
    );
  }

  //==========================================================================
  // Delete Driver
  //==========================================================================

  Future<void> deleteDriver(String uid) {
    return _firestoreService.deleteDocument(
      collection: FirestoreConstants.drivers,
      documentId: uid,
    );
  }

  //==========================================================================
  // Get Driver
  //==========================================================================

  Future<Driver?> getDriver(String uid) async {
    final snapshot = await _firestoreService.getDocument(
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

  Stream<Driver?> driverStream(String uid) {
    return _firestoreService
        .documentStream(FirestoreConstants.drivers, uid)
        .map((snapshot) {
          if (!snapshot.exists) {
            return null;
          }

          final data = snapshot.data();

          if (data == null) {
            return null;
          }

          return Driver.fromMap(data);
        });
  }

  //==========================================================================
  // Driver Online / Offline
  //==========================================================================

  Future<void> goOnline(String uid) async {
    await _functions.httpsCallable('setDriverOnlineStatus').call<void>({
      'isOnline': true,
    });
  }

  Future<void> goOffline(String uid) async {
    await _functions.httpsCallable('setDriverOnlineStatus').call<void>({
      'isOnline': false,
    });
  }

  //==========================================================================
  // Booking Availability
  //==========================================================================

  Future<void> setAvailable({required String uid, required bool available}) {
    throw UnsupportedError(
      'Driver availability is managed by the backend booking lifecycle.',
    );
  }

  Future<void> assignBooking({required String uid, required String bookingId}) {
    throw UnsupportedError(
      'Active bookings are assigned atomically by the backend.',
    );
  }

  Future<void> clearBooking(String uid) {
    throw UnsupportedError(
      'Active bookings are cleared atomically by the backend.',
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
    throw UnsupportedError(
      'Live driver coordinates are stored in Realtime Database.',
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
