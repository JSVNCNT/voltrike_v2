import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

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
    final raw = _database.ref('driver_locations/$driverId').onValue.map((event) {
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

    final output = StreamController<LatLng?>();
    StreamSubscription<LatLng?>? subscription;
    Timer? animation;
    LatLng? current;

    subscription = raw.listen((target) {
      animation?.cancel();
      if (target == null || current == null) {
        current = target;
        output.add(target);
        return;
      }

      final start = current!;
      var step = 0;
      const totalSteps = 10;
      animation = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        step++;
        final progress = step / totalSteps;
        current = LatLng(
          start.latitude + (target.latitude - start.latitude) * progress,
          start.longitude + (target.longitude - start.longitude) * progress,
        );
        output.add(current);
        if (step >= totalSteps) timer.cancel();
      });
    });

    output.onCancel = () async {
      animation?.cancel();
      await subscription?.cancel();
    };

    return output.stream;
  }
}
