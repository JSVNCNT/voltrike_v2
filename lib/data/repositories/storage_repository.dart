import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/voltrike_api.dart';

class StorageRepository {
  StorageRepository({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    VoltrikeApi? api,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = api ?? VoltrikeApi.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final VoltrikeApi _api;
  static const Uuid _uuid = Uuid();

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
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before uploading media.');
    final segments = path.split('/');
    if (segments.length < 3 || segments[1] != user.uid) {
      throw ArgumentError.value(
        path,
        'path',
        'Media path must belong to the signed-in user.',
      );
    }
    final field = segments.last.split('.').first;
    final targetType = field == 'profile' ? 'profile_image' : 'driver_document';
    final stagingPath = 'staging/${user.uid}/${_uuid.v4()}/${segments.last}';
    final reference = _storage.ref().child(stagingPath);

    final task = await reference.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'private, max-age=3600',
        customMetadata: const {'source': 'voltrike-registration'},
      ),
    );

    final result = await _api.operation('finalizeMedia', {
      'stagingPath': task.ref.fullPath,
      'generation': int.tryParse(task.metadata?.generation ?? ''),
      'targetType': targetType,
      'targetId': user.uid,
      'field': field,
    });
    final url = result['downloadUrl'];
    if (url is! String || url.isEmpty) {
      throw StateError('Media finalization returned no download URL.');
    }
    return url;
  }

  /// --------------------------------------------------------------------------
  /// Delete File
  /// --------------------------------------------------------------------------

  Future<void> deleteFile(String url) async {
    await _api.operation('deleteMyFinalizedMedia', {'url': url});
  }
}
