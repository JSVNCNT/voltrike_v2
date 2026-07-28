import 'package:equatable/equatable.dart';
import 'model_date_parser.dart';

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
    this.dateOfBirth,
    this.termsAcceptedAt,
    this.privacyAcceptedAt,
    this.termsVersion,
    this.privacyVersion,
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

  /// Collected for driver registration review; absent for legacy profiles.
  final DateTime? dateOfBirth;

  /// Audit fields for the legal documents accepted during registration.
  final DateTime? termsAcceptedAt;
  final DateTime? privacyAcceptedAt;
  final String? termsVersion;
  final String? privacyVersion;

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
    DateTime? dateOfBirth,
    DateTime? termsAcceptedAt,
    DateTime? privacyAcceptedAt,
    String? termsVersion,
    String? privacyVersion,
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
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt,
      termsVersion: termsVersion ?? this.termsVersion,
      privacyVersion: privacyVersion ?? this.privacyVersion,
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
      dateOfBirth: parseModelDate(map['dateOfBirth']),
      termsAcceptedAt: parseModelDate(map['termsAcceptedAt']),
      privacyAcceptedAt: parseModelDate(map['privacyAcceptedAt']),
      termsVersion: map['termsVersion'] as String?,
      privacyVersion: map['privacyVersion'] as String?,
      profileImage: map['profileImage'] ?? '',
      emailVerified: map['emailVerified'] ?? false,
      isActive: map['isActive'] ?? true,
      createdAt: parseModelDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: parseModelDate(map['updatedAt']) ?? DateTime.now(),
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
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'termsAcceptedAt': termsAcceptedAt?.toIso8601String(),
      'privacyAcceptedAt': privacyAcceptedAt?.toIso8601String(),
      'termsVersion': termsVersion,
      'privacyVersion': privacyVersion,
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
    dateOfBirth,
    termsAcceptedAt,
    privacyAcceptedAt,
    termsVersion,
    privacyVersion,
    profileImage,
    emailVerified,
    isActive,
    createdAt,
    updatedAt,
  ];
}
