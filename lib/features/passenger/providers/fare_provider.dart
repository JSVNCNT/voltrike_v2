import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ===========================================================================
/// Fare State
/// ===========================================================================
class FareState {
  const FareState({
    this.baseFare = 0,
    this.totalFare = 0,
    this.distanceMeters = 0,
    this.duration = '',
    this.additionalPassengers = 0,
    this.baggageCount = 0,
    this.boundarySurcharge = 0,
  });

  final double baseFare;

  final double totalFare;

  final int distanceMeters;

  final String duration;

  final int additionalPassengers;

  final int baggageCount;

  final double boundarySurcharge;

  FareState copyWith({
    double? baseFare,
    double? totalFare,
    int? distanceMeters,
    String? duration,
    int? additionalPassengers,
    int? baggageCount,
    double? boundarySurcharge,
  }) {
    return FareState(
      baseFare: baseFare ?? this.baseFare,
      totalFare: totalFare ?? this.totalFare,
      distanceMeters:
          distanceMeters ??
          this.distanceMeters,
      duration: duration ?? this.duration,
      additionalPassengers:
          additionalPassengers ??
          this.additionalPassengers,
      baggageCount:
          baggageCount ??
          this.baggageCount,
      boundarySurcharge:
          boundarySurcharge ??
          this.boundarySurcharge,
    );
  }
}

/// ===========================================================================
/// Fare Provider
/// ===========================================================================
class FareNotifier
    extends StateNotifier<FareState> {
  FareNotifier()
      : super(const FareState());

  void updateFare(
    FareState fare,
  ) {
    state = fare;
  }

  void reset() {
    state = const FareState();
  }
}

final fareProvider =
    StateNotifierProvider<
        FareNotifier,
        FareState>(
  (ref) => FareNotifier(),
);