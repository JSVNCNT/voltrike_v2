import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class Toda extends Equatable {
  const Toda({
    required this.id,
    required this.name,
    required this.regionCode,
    required this.provinceCode,
    required this.cityCode,
    required this.barangayCode,
    required this.isActive,
    required this.createdAt,
  });

  final String id;

  /// Example:
  /// "San Jose TODA"
  final String name;

  final String regionCode;
  final String provinceCode;
  final String cityCode;
  final String barangayCode;

  final bool isActive;

  final DateTime createdAt;

  Toda copyWith({
    String? id,
    String? name,
    String? regionCode,
    String? provinceCode,
    String? cityCode,
    String? barangayCode,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Toda(
      id: id ?? this.id,
      name: name ?? this.name,
      regionCode: regionCode ?? this.regionCode,
      provinceCode: provinceCode ?? this.provinceCode,
      cityCode: cityCode ?? this.cityCode,
      barangayCode: barangayCode ?? this.barangayCode,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Toda.fromMap(Map<String, dynamic> map) {
    return Toda(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      regionCode: map['regionCode'] ?? '',
      provinceCode: map['provinceCode'] ?? '',
      cityCode: map['cityCode'] ?? '',
      barangayCode: map['barangayCode'] ?? '',
      isActive: map['isActive'] ?? true,
      createdAt: _dateTime(map['createdAt']),
    );
  }

  static DateTime _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'regionCode': regionCode,
      'provinceCode': provinceCode,
      'cityCode': cityCode,
      'barangayCode': barangayCode,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    name,
    regionCode,
    provinceCode,
    cityCode,
    barangayCode,
    isActive,
    createdAt,
  ];
}
