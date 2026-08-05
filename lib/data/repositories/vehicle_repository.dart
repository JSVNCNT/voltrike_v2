import '../../core/constants/firestore_constants.dart';
import '../models/vehicle.dart';
import '../services/firestore_service.dart';

class VehicleRepository {
  VehicleRepository({FirestoreService? firestoreService})
    : _firestoreService = firestoreService ?? FirestoreService.instance;

  final FirestoreService _firestoreService;

  /// -------------------------------------------------------------------------
  /// Create Vehicle
  /// -------------------------------------------------------------------------

  Future<void> createVehicle(Vehicle vehicle) {
    throw UnsupportedError(
      'Vehicle creation is owned by Go registration authority.',
    );
  }

  /// -------------------------------------------------------------------------
  /// Update Vehicle
  /// -------------------------------------------------------------------------

  Future<void> updateVehicle(Vehicle vehicle) {
    throw UnsupportedError('Vehicle mutations are owned by Go authority.');
  }

  /// -------------------------------------------------------------------------
  /// Delete Vehicle
  /// -------------------------------------------------------------------------

  Future<void> deleteVehicle(String vehicleId) {
    throw UnsupportedError('Vehicle records are retained by Go authority.');
  }

  /// -------------------------------------------------------------------------
  /// Get Vehicle
  /// -------------------------------------------------------------------------

  Future<Vehicle?> getVehicle(String vehicleId) async {
    final snapshot = await _firestoreService.getDocument(
      FirestoreConstants.vehicles,
      vehicleId,
    );

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data();

    if (data == null) {
      return null;
    }

    return Vehicle.fromMap(data);
  }

  /// -------------------------------------------------------------------------
  /// Vehicle Stream
  /// -------------------------------------------------------------------------

  Stream<Vehicle?> vehicleStream(String vehicleId) {
    return _firestoreService
        .documentStream(FirestoreConstants.vehicles, vehicleId)
        .map((snapshot) {
          if (!snapshot.exists) {
            return null;
          }

          final data = snapshot.data();

          if (data == null) {
            return null;
          }

          return Vehicle.fromMap(data);
        });
  }
}
