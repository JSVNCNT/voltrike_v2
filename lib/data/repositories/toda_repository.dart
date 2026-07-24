import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_constants.dart';
import '../models/toda.dart';
import '../services/firestore_service.dart';

class TodaRepository {
  TodaRepository({
    FirestoreService? firestoreService,
  }) : _firestoreService =
            firestoreService ??
            FirestoreService.instance;

  final FirestoreService _firestoreService;

  CollectionReference<Map<String, dynamic>>
      get _collection =>
          _firestoreService.firestore.collection(
            FirestoreConstants.todas,
          );

  //==========================================================================
  // Get all active TODAs
  //==========================================================================

  Future<List<Toda>> getAllActiveTodas() async {
    final snapshot = await _collection.get();

    final todas = snapshot.docs
        .map(
          (doc) => Toda.fromMap({
            'id': doc.id,
            ...doc.data(),
          }),
        )
        .where(
          (toda) => toda.isActive,
        )
        .toList();

    todas.sort(
      (a, b) => a.name.compareTo(
        b.name,
      ),
    );

    return todas;
  }

  //==========================================================================
  // Get TODAs by Barangay
  //==========================================================================

  Future<List<Toda>> getTodasByBarangay(
    String barangayCode,
  ) async {
    final snapshot = await _collection
        .where(
          FirestoreConstants.barangay,
          isEqualTo: barangayCode,
        )
        .get();

    final todas = snapshot.docs
        .map(
          (doc) => Toda.fromMap({
            'id': doc.id,
            ...doc.data(),
          }),
        )
        .where(
          (toda) => toda.isActive,
        )
        .toList();

    todas.sort(
      (a, b) => a.name.compareTo(
        b.name,
      ),
    );

    return todas;
  }

  //==========================================================================
  // Get TODA
  //==========================================================================

  Future<Toda?> getToda(
    String id,
  ) async {
    final snapshot = await _collection
        .doc(id)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    return Toda.fromMap({
      'id': snapshot.id,
      ...snapshot.data()!,
    });
  }

  
  //==========================================================================
  // Create TODA
  //==========================================================================

  Future<void> createToda(
    Toda toda,
  ) async {
    await _collection
        .doc(toda.id)
        .set(toda.toMap());
  }

  //==========================================================================
  // Update TODA
  //==========================================================================

  Future<void> updateToda(
    Toda toda,
  ) async {
    await _collection
        .doc(toda.id)
        .update(toda.toMap());
  }

  //==========================================================================
  // Delete TODA
  //==========================================================================

  Future<void> deleteToda(
    String id,
  ) async {
    await _collection
        .doc(id)
        .delete();
  }

  //==========================================================================
  // TODA Stream
  //==========================================================================

  Stream<List<Toda>> todaStream() {
    return _collection.snapshots().map(
      (snapshot) {
        final todas = snapshot.docs
            .map(
              (doc) => Toda.fromMap({
                'id': doc.id,
                ...doc.data(),
              }),
            )
            .where(
              (toda) => toda.isActive,
            )
            .toList();

        todas.sort(
          (a, b) => a.name.compareTo(
            b.name,
          ),
        );

        return todas;
      },
    );
  }
}