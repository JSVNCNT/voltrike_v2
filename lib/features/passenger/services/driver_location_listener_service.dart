import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Listens to an assigned driver's current RTDB location.
///
/// Firestore owns durable booking state. RTDB owns high-frequency coordinates
/// at `driver_locations/{driverId}`.
class DriverLocationListenerService {
  DriverLocationListenerService._();

  static final DriverLocationListenerService instance =
      DriverLocationListenerService._();

  final FirebaseDatabase _database = FirebaseDatabase.instance;

  Stream<LatLng?> listen(String driverId) {
    return _database.ref('driver_locations/$driverId').onValue.map((event) {
      final value = event.snapshot.value;

      if (value is! Map) {
        return null;
      }

      final data = Map<Object?, Object?>.from(value);
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();

      if (latitude == null || longitude == null || data['online'] == false) {
        return null;
      }

      return LatLng(latitude, longitude);
    });
  }
}
