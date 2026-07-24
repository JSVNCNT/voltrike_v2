import 'dart:math';

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
    required this.baseFare,
    required this.includedMeters,
    required this.distanceStepMeters,
    required this.distanceStepPrice,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.outsideTodaSurcharge,
  });

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
}

/// ===========================================================================
/// Development Configuration
///
/// Placeholder values until Firestore Admin Settings
/// are implemented.
/// ===========================================================================
const FareConfiguration devFareConfiguration =
    FareConfiguration(
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
    required this.totalFare,
    required this.distanceMeters,
    required this.additionalPassengers,
    required this.baggageCount,
  });

  final double baseFare;

  final double distanceFare;

  final double additionalPassengerFee;

  final double baggageFee;

  final double boundarySurcharge;

  final double totalFare;

  final int distanceMeters;

  final int additionalPassengers;

  final int baggageCount;
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
  }) {
    //----------------------------------------------------------------------
    // Distance Charge
    //----------------------------------------------------------------------

    final chargeableMeters =
        max(0, distanceMeters - config.includedMeters);

    final distanceSteps =
        (chargeableMeters / config.distanceStepMeters)
            .ceil();

    final distanceFare =
        distanceSteps * config.distanceStepPrice;

    //----------------------------------------------------------------------
    // Additional Passenger
    //----------------------------------------------------------------------

    final additionalPassengers =
        max(0, passengerCount - 1);

    final passengerFee =
        additionalPassengers *
            config.additionalPassengerFee;

    //----------------------------------------------------------------------
    // Baggage
    //----------------------------------------------------------------------

    final baggageFee =
        baggageCount * config.baggageFee;

    //----------------------------------------------------------------------
    // Outside TODA
    //----------------------------------------------------------------------

    final boundaryFee =
        isOutsideToda
            ? config.outsideTodaSurcharge
            : 0.0;

    //----------------------------------------------------------------------
    // Total
    //----------------------------------------------------------------------

    final total =
        config.baseFare +
        distanceFare +
        passengerFee +
        baggageFee +
        boundaryFee;

    return FareResult(
      baseFare: config.baseFare,
      distanceFare: distanceFare,
      additionalPassengerFee: passengerFee,
      baggageFee: baggageFee,
      boundarySurcharge: boundaryFee,
      totalFare: total,
      distanceMeters: distanceMeters,
      additionalPassengers:
          additionalPassengers,
      baggageCount: baggageCount,
    );
  }
}