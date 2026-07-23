import 'package:flutter_riverpod/flutter_riverpod.dart';

class TripState {
  const TripState({
    this.tripId,
    this.driverId,
    this.isActive = false,
  });

  final String? tripId;

  final String? driverId;

  final bool isActive;

  TripState copyWith({
    String? tripId,
    String? driverId,
    bool? isActive,
  }) {
    return TripState(
      tripId: tripId ?? this.tripId,
      driverId: driverId ?? this.driverId,
      isActive: isActive ?? this.isActive,
    );
  }
}

class TripNotifier
    extends StateNotifier<TripState> {
  TripNotifier()
      : super(
          const TripState(),
        );

  void startTrip({
    required String tripId,
    required String driverId,
  }) {
    state = TripState(
      tripId: tripId,
      driverId: driverId,
      isActive: true,
    );
  }

  void endTrip() {
    state = const TripState();
  }
}

final tripProvider =
    StateNotifierProvider<
        TripNotifier,
        TripState>(
  (ref) => TripNotifier(),
);