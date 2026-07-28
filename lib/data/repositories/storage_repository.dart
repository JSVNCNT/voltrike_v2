import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageRepository {
  StorageRepository({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// --------------------------------------------------------------------------
  /// Upload File
  /// --------------------------------------------------------------------------

  Future<String> uploadFile({required String path, required File file}) async {
    const maxUploadBytes = 4 * 1024 * 1024;
    if (await file.length() > maxUploadBytes) {
      throw const FileSystemException(
        'Registration images must be 4 MB or smaller.',
      );
    }
    final reference = _storage.ref().child(path);

    final task = await reference.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'private, max-age=3600',
        customMetadata: const {'source': 'voltrike-registration'},
      ),
    );

    return task.ref.getDownloadURL();
  }

  /// --------------------------------------------------------------------------
  /// Delete File
  /// --------------------------------------------------------------------------

  Future<void> deleteFile(String url) async {
    await _storage.refFromURL(url).delete();
  }
}
