import 'package:equatable/equatable.dart';

class Fare extends Equatable {
  const Fare({
    required this.baseFare,
    required this.distanceStepMeters,
    required this.distanceStepPrice,
    required this.additionalPassengerFee,
    required this.baggageFee,
    required this.outOfBarangayFee,
    required this.updatedAt,
  });

  final double baseFare;

  final int distanceStepMeters;
  final double distanceStepPrice;

  final double additionalPassengerFee;
  final double baggageFee;
  final double outOfBarangayFee;

  final DateTime updatedAt;

  Fare copyWith({
    double? baseFare,
    int? distanceStepMeters,
    double? distanceStepPrice,
    double? additionalPassengerFee,
    double? baggageFee,
    double? outOfBarangayFee,
    DateTime? updatedAt,
  }) {
    return Fare(
      baseFare: baseFare ?? this.baseFare,
      distanceStepMeters:
          distanceStepMeters ?? this.distanceStepMeters,
      distanceStepPrice:
          distanceStepPrice ?? this.distanceStepPrice,
      additionalPassengerFee:
          additionalPassengerFee ?? this.additionalPassengerFee,
      baggageFee: baggageFee ?? this.baggageFee,
      outOfBarangayFee:
          outOfBarangayFee ?? this.outOfBarangayFee,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Fare.fromMap(Map<String, dynamic> map) {
    return Fare(
      baseFare: (map['baseFare'] ?? 0).toDouble(),
      distanceStepMeters: map['distanceStepMeters'] ?? 500,
      distanceStepPrice:
          (map['distanceStepPrice'] ?? 0).toDouble(),
      additionalPassengerFee:
          (map['additionalPassengerFee'] ?? 0).toDouble(),
      baggageFee: (map['baggageFee'] ?? 0).toDouble(),
      outOfBarangayFee:
          (map['outOfBarangayFee'] ?? 0).toDouble(),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'baseFare': baseFare,
      'distanceStepMeters': distanceStepMeters,
      'distanceStepPrice': distanceStepPrice,
      'additionalPassengerFee': additionalPassengerFee,
      'baggageFee': baggageFee,
      'outOfBarangayFee': outOfBarangayFee,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        baseFare,
        distanceStepMeters,
        distanceStepPrice,
        additionalPassengerFee,
        baggageFee,
        outOfBarangayFee,
        updatedAt,
      ];
}