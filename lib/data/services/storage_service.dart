import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService._();

  static final StorageService instance =
      StorageService._();

  final FirebaseStorage _storage =
      FirebaseStorage.instance;

  Future<String> uploadImage({
    required File file,
    required String path,
  }) async {
    final reference = _storage.ref(path);

    final task = await reference.putFile(file);

    return task.ref.getDownloadURL();
  }

  Future<void> deleteFile(
    String path,
  ) {
    return _storage.ref(path).delete();
  }

  Future<String> getDownloadUrl(
    String path,
  ) {
    return _storage.ref(path).getDownloadURL();
  }
}