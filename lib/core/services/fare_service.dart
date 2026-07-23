import 'dart:math';

/// ===========================================================================
/// Fare Configuration
///
/// Loaded from Firestore (Admin Portal).
/// ===========================================================================
class FareConfiguration {
  const FareConfiguration({
    required this.baseFare,
    required this.includedMeters,
    required this.additionalPerMeter,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.outsideTodaSurcharge,
  });

  final double baseFare;

  final int includedMeters;

  /// Charge per meter after the included distance.
  final double additionalPerMeter;

  final double additionalPassengerFee;

  final double baggageFee;

  final double outsideTodaSurcharge;
}

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
  });

  final double baseFare;

  final double distanceFare;

  final double additionalPassengerFee;

  final double baggageFee;

  final double boundarySurcharge;

  final double totalFare;

  final int distanceMeters;
}

/// ===========================================================================
/// Fare Service
///
/// Calculates passenger fares.
///
/// Pricing values should eventually be loaded from Firestore
/// and managed through the Admin Portal.
/// ===========================================================================
class FareService {
  const FareService._();

  static FareResult calculateFare({
    required FareConfiguration config,
    required int distanceMeters,

    /// Total passengers including the booking passenger.
    int passengerCount = 1,

    int baggageCount = 0,

    bool isOutsideToda = false,
  }) {
    //=======================================================================
    // Distance Fare
    //=======================================================================

    final int chargeableMeters = max(
      0,
      distanceMeters - config.includedMeters,
    );

    final double distanceFare =
        chargeableMeters *
            config.additionalPerMeter;

    //=======================================================================
    // Additional Passenger Fee
    //=======================================================================

    final int additionalPassengers =
        max(0, passengerCount - 1);

    final double passengerFee =
        additionalPassengers *
            config.additionalPassengerFee;

    //=======================================================================
    // Baggage Fee
    //=======================================================================

    final double baggageFee =
        baggageCount * config.baggageFee;

    //=======================================================================
    // Outside TODA Surcharge
    //=======================================================================

    final double boundaryFee =
        isOutsideToda
            ? config.outsideTodaSurcharge
            : 0.0;

    //=======================================================================
    // Total
    //=======================================================================

    final double total =
        config.baseFare +
        distanceFare +
        passengerFee +
        baggageFee +
        boundaryFee;

    return FareResult(
      baseFare: config.baseFare,
      distanceFare: distanceFare,
      additionalPassengerFee:
          passengerFee,
      baggageFee: baggageFee,
      boundarySurcharge:
          boundaryFee,
      totalFare: total,
      distanceMeters:
          distanceMeters,
    );
  }
}