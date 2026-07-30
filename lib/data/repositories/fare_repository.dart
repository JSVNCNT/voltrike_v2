import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/fare_service.dart';

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
        final data = snapshot.data()!;
        return FareConfiguration(
          version: _positiveInteger(
            data['version'],
            devFareConfiguration.version,
          ),
          baseFare: _nonNegativeCurrency(
            data['baseFare'],
            devFareConfiguration.baseFare,
          ),
          includedMeters: _positiveInteger(
            data['includedMeters'],
            devFareConfiguration.includedMeters,
          ),
          distanceStepMeters: _positiveInteger(
            data['distanceStepMeters'],
            devFareConfiguration.distanceStepMeters,
          ),
          distanceStepPrice: _nonNegativeCurrency(
            data['distanceStepPrice'],
            devFareConfiguration.distanceStepPrice,
          ),
          additionalPassengerFee: _nonNegativeCurrency(
            data['additionalPassengerFee'],
            devFareConfiguration.additionalPassengerFee,
          ),
          baggageFee: _nonNegativeCurrency(
            data['baggageFee'],
            devFareConfiguration.baggageFee,
          ),
          outsideTodaSurcharge: _nonNegativeCurrency(
            data['outsideTodaSurcharge'] ?? data['outOfBarangayFee'],
            devFareConfiguration.outsideTodaSurcharge,
          ),
        );
      },
    );
  }

  static int _positiveInteger(Object? value, int fallback) {
    return value is num && value.isFinite && value > 0 && value == value.round()
        ? value.round()
        : fallback;
  }

  static double _nonNegativeCurrency(Object? value, double fallback) {
    return value is num && value.isFinite && value >= 0
        ? FareService.roundCurrency(value.toDouble())
        : fallback;
  }
}
