import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/emergency_contact.dart';

class EmergencyContactRepository {
  EmergencyContactRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _contacts(String uid) =>
      _firestore.collection('users').doc(uid).collection('emergencyContacts');

  Stream<List<EmergencyContact>> watch(String uid) {
    return _contacts(uid)
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(EmergencyContact.fromFirestore).toList(),
        );
  }

  Future<void> save(String uid, EmergencyContact contact) {
    if (contact.name.trim().isEmpty || contact.phoneNumber.trim().isEmpty) {
      throw ArgumentError('Emergency contact name and phone are required.');
    }
    return _contacts(
      uid,
    ).doc(contact.id).set(contact.toFirestore(), SetOptions(merge: true));
  }

  Future<void> remove(String uid, String contactId) {
    return _contacts(uid).doc(contactId).delete();
  }
}
