import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseFirestore get firestore => _firestore;

  Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
    String collection,
    String documentId, {
    GetOptions? options,
  }) {
    return _firestore.collection(collection).doc(documentId).get(options);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> documentStream(
    String collection,
    String documentId,
  ) {
    return _firestore.collection(collection).doc(documentId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> collectionStream(
    String collection,
  ) {
    return _firestore.collection(collection).snapshots();
  }

  Future<void> setDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) {
    return _firestore
        .collection(collection)
        .doc(documentId)
        .set(data, SetOptions(merge: merge));
  }

  Future<void> updateDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return _firestore.collection(collection).doc(documentId).update(data);
  }

  Future<void> deleteDocument({
    required String collection,
    required String documentId,
  }) {
    return _firestore.collection(collection).doc(documentId).delete();
  }

  WriteBatch batch() {
    return _firestore.batch();
  }

  Future<T> runTransaction<T>(TransactionHandler<T> handler) {
    return _firestore.runTransaction(handler);
  }
}
