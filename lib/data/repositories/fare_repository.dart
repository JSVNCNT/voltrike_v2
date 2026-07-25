import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/fare_service.dart';
import '../models/fare.dart';

/// Reads the centrally managed PHP fare configuration. The development
/// configuration remains a safe fallback while the first document is absent.
class FareRepository {
  FareRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<FareConfiguration> watchConfiguration() {
    return _firestore.collection('settings').doc('fare_config').snapshots().map(
          (snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          return devFareConfiguration;
        }
        final fare = Fare.fromMap(snapshot.data()!);
        return FareConfiguration(
          baseFare: fare.baseFare,
          includedMeters: fare.includedMeters,
          distanceStepMeters: fare.distanceStepMeters,
          distanceStepPrice: fare.distanceStepPrice,
          additionalPassengerFee: fare.additionalPassengerFee,
          baggageFee: fare.baggageFee,
          outsideTodaSurcharge: fare.outOfBarangayFee,
        );
      },
    );
  }
}
