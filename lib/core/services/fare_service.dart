import 'dart:math';

import '../../data/models/ride_type.dart';

/// ===========================================================================
/// Fare Configuration
///
/// Pricing configuration.
///
/// During development this can be hardcoded.
/// Later it will be loaded from Firestore and managed
/// through the Admin Portal.
/// ===========================================================================
class FareConfiguration {
  const FareConfiguration({
    this.version = 1,
    required this.baseFare,
    required this.includedMeters,
    required this.distanceStepMeters,
    required this.distanceStepPrice,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.outsideTodaSurcharge,
    this.additionalDropoffFee = 10,
    this.eTrikeSurcharge = 0,
    this.eTuktukSurcharge = 10,
    this.eTrikeEnabled = true,
    this.eTuktukEnabled = true,
  });

  final int version;

  /// Base fare.
  final double baseFare;

  /// Distance included in the base fare.
  final int includedMeters;

  /// Charge interval.
  ///
  /// Example:
  /// Every 500 meters.
  final int distanceStepMeters;

  /// Price charged every distance step.
  ///
  /// Example:
  /// ₱5 every 500 meters.
  final double distanceStepPrice;

  /// Fee for every additional passenger.
  final double additionalPassengerFee;

  /// Fee per baggage.
  final double baggageFee;

  /// Outside TODA surcharge.
  final double outsideTodaSurcharge;
  final double additionalDropoffFee;
  final double eTrikeSurcharge;
  final double eTuktukSurcharge;
  final bool eTrikeEnabled;
  final bool eTuktukEnabled;

  bool isRideTypeEnabled(RideType rideType) => switch (rideType) {
    RideType.eTrike => eTrikeEnabled,
    RideType.eTuktuk => eTuktukEnabled,
  };

  double rideTypeSurcharge(RideType rideType) => switch (rideType) {
    RideType.eTrike => eTrikeSurcharge,
    RideType.eTuktuk => eTuktukSurcharge,
  };
}

/// ===========================================================================
/// Development Configuration
///
/// Placeholder values until Firestore Admin Settings
/// are implemented.
/// ===========================================================================
const FareConfiguration devFareConfiguration = FareConfiguration(
  baseFare: 20,

  // First kilometer included.
  includedMeters: 1000,

  // Every additional 500 meters.
  distanceStepMeters: 500,

  // ₱5 every 500 meters.
  distanceStepPrice: 5,

  // Every additional passenger.
  additionalPassengerFee: 40,

  // Per baggage.
  baggageFee: 20,

  // Outside TODA.
  outsideTodaSurcharge: 20,

  // One flat charge when a passenger adds a second drop-off.
  additionalDropoffFee: 10,
  eTrikeSurcharge: 0,
  eTuktukSurcharge: 10,
);

/// ===========================================================================
/// Fare Result
/// ===========================================================================
class FareResult {
  const FareResult({
    required this.baseFare,
    required this.distanceFare,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.boundarySurcharge,
    required this.additionalDropoffFare,
    required this.totalFare,
    required this.distanceMeters,
    required this.additionalPassengers,
    required this.baggageCount,
    required this.rideTypeFare,
  });

  final double baseFare;

  final double distanceFare;

  final double additionalPassengerFee;

  final double baggageFee;

  final double boundarySurcharge;
  final double additionalDropoffFare;

  final double totalFare;

  final int distanceMeters;

  final int additionalPassengers;

  final int baggageCount;
  final double rideTypeFare;
}

/// ===========================================================================
/// Fare Service
///
/// Calculates the passenger fare.
///
/// Formula
///
/// Base Fare
/// + Distance Charge
/// + Additional Passenger Fee
/// + Baggage Fee
/// + Outside TODA Surcharge
/// ===========================================================================
class FareService {
  const FareService._();

  static FareResult calculateFare({
    required FareConfiguration config,
    required int distanceMeters,

    /// Total passengers including the passenger
    /// making the booking.
    int passengerCount = 1,

    int baggageCount = 0,

    bool isOutsideToda = false,

    int dropoffCount = 1,
    RideType rideType = RideType.eTrike,
  }) {
    //----------------------------------------------------------------------
    // Distance Charge
    //----------------------------------------------------------------------

    final chargeableMeters = max(0, distanceMeters - config.includedMeters);

    final distanceSteps = (chargeableMeters / max(1, config.distanceStepMeters))
        .ceil();

    final distanceFareCentavos =
        distanceSteps * _toCentavos(config.distanceStepPrice);

    //----------------------------------------------------------------------
    // Additional Passenger
    //----------------------------------------------------------------------

    final additionalPassengers = max(0, passengerCount - 1);

    final passengerFeeCentavos =
        additionalPassengers * _toCentavos(config.additionalPassengerFee);

    //----------------------------------------------------------------------
    // Baggage
    //----------------------------------------------------------------------

    final normalizedBaggageCount = max(0, baggageCount);
    final baggageFeeCentavos =
        normalizedBaggageCount * _toCentavos(config.baggageFee);

    //----------------------------------------------------------------------
    // Outside TODA
    //----------------------------------------------------------------------

    final boundaryFeeCentavos = isOutsideToda
        ? _toCentavos(config.outsideTodaSurcharge)
        : 0;
    final additionalDropoffs = max(0, dropoffCount - 1);
    final additionalDropoffFeeCentavos =
        additionalDropoffs * _toCentavos(config.additionalDropoffFee);
    final rideTypeFareCentavos = _toCentavos(
      config.rideTypeSurcharge(rideType),
    );

    //----------------------------------------------------------------------
    // Total
    //----------------------------------------------------------------------

    final baseFareCentavos = _toCentavos(config.baseFare);
    final totalCentavos =
        baseFareCentavos +
        distanceFareCentavos +
        passengerFeeCentavos +
        baggageFeeCentavos +
        boundaryFeeCentavos +
        additionalDropoffFeeCentavos +
        rideTypeFareCentavos;

    return FareResult(
      baseFare: _fromCentavos(baseFareCentavos),
      distanceFare: _fromCentavos(distanceFareCentavos),
      additionalPassengerFee: _fromCentavos(passengerFeeCentavos),
      baggageFee: _fromCentavos(baggageFeeCentavos),
      boundarySurcharge: _fromCentavos(boundaryFeeCentavos),
      additionalDropoffFare: _fromCentavos(additionalDropoffFeeCentavos),
      totalFare: _fromCentavos(totalCentavos),
      distanceMeters: distanceMeters,
      additionalPassengers: additionalPassengers,
      baggageCount: normalizedBaggageCount,
      rideTypeFare: _fromCentavos(rideTypeFareCentavos),
    );
  }

  static double roundCurrency(double value) =>
      _fromCentavos(_toCentavos(value));

  static double _fromCentavos(int value) => value / 100;

  /// Converts the decimal text representation instead of multiplying a binary
  /// floating-point value. This keeps Dart aligned with the Node authority at
  /// half-cent boundaries such as 10.075 -> 10.08.
  static int _toCentavos(num value) {
    final number = value.toDouble();
    if (!number.isFinite) return 0;

    final negative = number.isNegative;
    final parts = number.abs().toString().toLowerCase().split('e');
    final coefficient = parts.first;
    final exponent = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
    final decimalParts = coefficient.split('.');
    final fraction = decimalParts.length == 2 ? decimalParts[1] : '';
    final digits = BigInt.parse('${decimalParts.first}$fraction');
    final shift = 2 + exponent - fraction.length;

    BigInt centavos;
    if (shift >= 0) {
      centavos = digits * BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      centavos = digits ~/ divisor;
      final remainder = digits.remainder(divisor);
      if (remainder * BigInt.two >= divisor) {
        centavos += BigInt.one;
      }
    }
    final result = centavos.toInt();
    return negative ? -result : result;
  }
}
