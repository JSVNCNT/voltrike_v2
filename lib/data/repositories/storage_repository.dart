import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageRepository {
  StorageRepository({
    FirebaseStorage? storage,
  }) : _storage =
            storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// --------------------------------------------------------------------------
  /// Upload File
  /// --------------------------------------------------------------------------

  Future<String> uploadFile({
    required String path,
    required File file,
  }) async {
    final reference = _storage.ref().child(path);

    final task = await reference.putFile(file);

    return task.ref.getDownloadURL();
  }

  /// --------------------------------------------------------------------------
  /// Delete File
  /// --------------------------------------------------------------------------

  Future<void> deleteFile(
    String url,
  ) async {
    await _storage.refFromURL(url).delete();
  }
}