import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/services/fare_service.dart';
import 'package:voltrike_v2/data/models/ride_type.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/fare_parity_v1.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = fixture['cases'] as List<dynamic>;

  for (final rawCase in cases) {
    final fareCase = Map<String, dynamic>.from(rawCase as Map);
    test('shared fare parity: ${fareCase['name']}', () {
      final rawConfig = fareCase['config'];
      final config = rawConfig is Map
          ? _configuration(Map<String, dynamic>.from(rawConfig))
          : devFareConfiguration;
      final input = Map<String, dynamic>.from(fareCase['input'] as Map);
      final expected = Map<String, dynamic>.from(fareCase['expected'] as Map);

      final result = FareService.calculateFare(
        config: config,
        distanceMeters: (input['distanceMeters'] as num).round(),
        passengerCount: (input['additionalPassengers'] as num).round() + 1,
        baggageCount: (input['baggageCount'] as num).round(),
        isOutsideToda: input['isOutsideToda'] == true,
      );

      expect(result.baseFare, expected['baseFare']);
      expect(result.distanceFare, expected['distanceFare']);
      expect(
        result.additionalPassengerFee,
        expected['additionalPassengerFare'],
      );
      expect(result.baggageFee, expected['baggageFare']);
      expect(result.boundarySurcharge, expected['boundarySurcharge']);
      expect(result.totalFare, expected['total']);
    });
  }

  test('half-cent currency values round identically to Node', () {
    expect(FareService.roundCurrency(10.075), 10.08);
    expect(FareService.roundCurrency(1.005), 1.01);
  });

  test('E-Tuktuk adjustment is included exactly once', () {
    final result = FareService.calculateFare(
      config: devFareConfiguration,
      distanceMeters: 1000,
      rideType: RideType.eTuktuk,
    );
    expect(result.rideTypeFare, 10);
    expect(result.totalFare, 30);
  });
}

FareConfiguration _configuration(Map<String, dynamic> data) {
  double currency(String key, double fallback) =>
      data[key] is num ? (data[key] as num).toDouble() : fallback;
  int integer(String key, int fallback) =>
      data[key] is num ? (data[key] as num).round() : fallback;

  return FareConfiguration(
    version: integer('version', devFareConfiguration.version),
    baseFare: currency('baseFare', devFareConfiguration.baseFare),
    includedMeters: integer(
      'includedMeters',
      devFareConfiguration.includedMeters,
    ),
    distanceStepMeters: integer(
      'distanceStepMeters',
      devFareConfiguration.distanceStepMeters,
    ),
    distanceStepPrice: currency(
      'distanceStepPrice',
      devFareConfiguration.distanceStepPrice,
    ),
    additionalPassengerFee: currency(
      'additionalPassengerFee',
      devFareConfiguration.additionalPassengerFee,
    ),
    baggageFee: currency('baggageFee', devFareConfiguration.baggageFee),
    outsideTodaSurcharge: currency(
      'outsideTodaSurcharge',
      devFareConfiguration.outsideTodaSurcharge,
    ),
  );
}
