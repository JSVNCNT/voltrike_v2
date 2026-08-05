import 'dart:io';

import '../../core/constants/firestore_constants.dart';
import '../models/driver.dart';
import '../services/firestore_service.dart';
import 'storage_repository.dart';

class DriverRepository {
  DriverRepository({
    FirestoreService? firestoreService,
    StorageRepository? storageRepository,
  }) : _firestoreService = firestoreService ?? FirestoreService.instance,
       _storageRepository = storageRepository ?? StorageRepository();

  final FirestoreService _firestoreService;

  final StorageRepository _storageRepository;

  //==========================================================================
  // Create Driver
  //==========================================================================

  Future<void> createDriver(Driver driver) {
    throw UnsupportedError(
      'Driver creation is owned by Go registration authority.',
    );
  }

  //==========================================================================
  // Update Driver
  //==========================================================================

  Future<void> updateDriver(Driver driver) {
    throw UnsupportedError('Driver mutations are owned by Go authority.');
  }

  //==========================================================================
  // Delete Driver
  //==========================================================================

  Future<void> deleteDriver(String uid) {
    throw UnsupportedError('Driver records are retained by Go authority.');
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

  Future<String?> getPendingReceiptBookingId(String uid) async {
    final snapshot = await _firestoreService.getDocument(
      FirestoreConstants.drivers,
      uid,
    );
    final value = snapshot.data()?['pendingReceiptBookingId'];
    return value is String && value.isNotEmpty ? value : null;
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
    throw UnsupportedError(
      'Driver online state is owned by the session lease controller.',
    );
  }

  Future<void> goOffline(String uid) async {
    throw UnsupportedError(
      'Driver online state is owned by the session lease controller.',
    );
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
