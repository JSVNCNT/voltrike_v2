import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/fare.dart';

void main() {
  group('Fare boundary surcharge parsing', () {
    test('uses the current outsideTodaSurcharge field', () {
      final fare = Fare.fromMap({
        'baseFare': 20,
        'includedMeters': 1000,
        'distanceStepMeters': 500,
        'distanceStepPrice': 5,
        'additionalPassengerFee': 40,
        'baggageFee': 20,
        'outsideTodaSurcharge': 35,
        'outOfBarangayFee': 10,
        'updatedAt': '2026-07-29T00:00:00Z',
      });

      expect(fare.outOfBarangayFee, 35);
    });

    test('keeps the legacy outOfBarangayFee fallback', () {
      final fare = Fare.fromMap({
        'baseFare': 20,
        'includedMeters': 1000,
        'distanceStepMeters': 500,
        'distanceStepPrice': 5,
        'additionalPassengerFee': 40,
        'baggageFee': 20,
        'outOfBarangayFee': 18,
        'updatedAt': '2026-07-29T00:00:00Z',
      });

      expect(fare.outOfBarangayFee, 18);
    });
  });
}
