import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.phoneNumber,
    required this.role,
    required this.profileImage,
    required this.emailVerified,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.todaId,
  });

  final String uid;
  final String email;

  final String firstName;
  final String middleName;
  final String lastName;

  final String phoneNumber;

  /// passenger | driver | developer_admin | toda_admin
  final String role;

  /// TODA assigned to the user.
  ///
  /// - Passenger: null
  /// - Driver: assigned after approval
  /// - TODA Admin: assigned during creation
  /// - Developer Admin: null
  final String? todaId;

  final String profileImage;

  final bool emailVerified;

  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get fullName {
    if (middleName.trim().isEmpty) {
      return '$firstName $lastName';
    }

    return '$firstName $middleName $lastName';
  }

  bool get isPassenger => role == 'passenger';

  bool get isDriver => role == 'driver';

  bool get isDeveloperAdmin => role == 'developer_admin';

  bool get isTodaAdmin => role == 'toda_admin';

  AppUser copyWith({
    String? uid,
    String? email,
    String? firstName,
    String? middleName,
    String? lastName,
    String? phoneNumber,
    String? role,
    String? todaId,
    String? profileImage,
    bool? emailVerified,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      todaId: todaId ?? this.todaId,
      profileImage: profileImage ?? this.profileImage,
      emailVerified: emailVerified ?? this.emailVerified,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      firstName: map['firstName'] ?? '',
      middleName: map['middleName'] ?? '',
      lastName: map['lastName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      role: map['role'] ?? 'passenger',
      todaId: map['todaId'],
      profileImage: map['profileImage'] ?? '',
      emailVerified: map['emailVerified'] ?? false,
      isActive: map['isActive'] ?? true,
      createdAt: DateTime.tryParse(
            map['createdAt'] ?? '',
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            map['updatedAt'] ?? '',
          ) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'role': role,
      'todaId': todaId,
      'profileImage': profileImage,
      'emailVerified': emailVerified,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        firstName,
        middleName,
        lastName,
        phoneNumber,
        role,
        todaId,
        profileImage,
        emailVerified,
        isActive,
        createdAt,
        updatedAt,
      ];
}