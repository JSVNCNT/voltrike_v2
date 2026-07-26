import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
  });

  final String id;
  final String name;
  final String phoneNumber;
  final String relationship;

  factory EmergencyContact.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return EmergencyContact(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      relationship: data['relationship'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name.trim(),
    'phoneNumber': phoneNumber.trim(),
    'relationship': relationship.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
