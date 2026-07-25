import 'package:cloud_firestore/cloud_firestore.dart';

class ReportRepository {
  ReportRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  Future<void> create({required String bookingId, required String reporterId, required String reportedUserId, required String category, required String details}) {
    return _firestore.collection('reports').add({
      'bookingId': bookingId,
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'category': category,
      'details': details,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
