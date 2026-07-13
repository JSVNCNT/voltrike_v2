import 'package:equatable/equatable.dart';

class Vehicle extends Equatable {
  const Vehicle({
    required this.id,
    required this.driverId,
    required this.plateNumber,
    required this.vehicleNumber,
    required this.model,
    required this.color,
    required this.capacity,
    required this.isVerified,
    required this.createdAt,
  });

  final String id;
  final String driverId;

  final String plateNumber;
  final String vehicleNumber;

  final String model;
  final String color;

  final int capacity;

  final bool isVerified;

  final DateTime createdAt;

  Vehicle copyWith({
    String? id,
    String? driverId,
    String? plateNumber,
    String? vehicleNumber,
    String? model,
    String? color,
    int? capacity,
    bool? isVerified,
    DateTime? createdAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      plateNumber: plateNumber ?? this.plateNumber,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      model: model ?? this.model,
      color: color ?? this.color,
      capacity: capacity ?? this.capacity,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] ?? '',
      driverId: map['driverId'] ?? '',
      plateNumber: map['plateNumber'] ?? '',
      vehicleNumber: map['vehicleNumber'] ?? '',
      model: map['model'] ?? '',
      color: map['color'] ?? '',
      capacity: map['capacity'] ?? 4,
      isVerified: map['isVerified'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'driverId': driverId,
      'plateNumber': plateNumber,
      'vehicleNumber': vehicleNumber,
      'model': model,
      'color': color,
      'capacity': capacity,
      'isVerified': isVerified,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        driverId,
        plateNumber,
        vehicleNumber,
        model,
        color,
        capacity,
        isVerified,
        createdAt,
      ];
}