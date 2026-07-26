import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Development-only Firebase Emulator Suite configuration.
///
/// Emulator mode must be requested explicitly with:
/// `--dart-define=USE_FIREBASE_EMULATORS=true`.
///
/// The demo project has no live Firebase resources. Initializing every
/// Firebase SDK with this project ID makes accidental fall-through fail
/// instead of touching the connected `voltrike-v2` project.
class FirebaseEmulatorConfig {
  const FirebaseEmulatorConfig._();

  static const bool enabled = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static const String projectId = 'demo-voltrike';
  static const String testRole = String.fromEnvironment(
    'VOLTRIKE_TEST_ROLE',
  );

  static String get host {
    if (kIsWeb) return '127.0.0.1';
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
  }

  static const FirebaseOptions firebaseOptions = FirebaseOptions(
    apiKey: 'demo-voltrike-api-key',
    appId: '1:000000000000:android:demo-voltrike',
    messagingSenderId: '000000000000',
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    databaseURL: 'https://$projectId-default-rtdb.firebaseio.com',
    storageBucket: '$projectId.appspot.com',
  );

  static Future<void> connect() async {
    if (!enabled) return;
    if (kReleaseMode) {
      throw StateError('Firebase emulator mode is forbidden in release builds.');
    }
    if (Firebase.app().options.projectId != projectId) {
      throw StateError(
        'Emulator mode must initialize Firebase with $projectId.',
      );
    }

    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseDatabase.instance.useDatabaseEmulator(host, 9000);
    FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).useFunctionsEmulator(host, 5001);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }

  static Future<void> signInTestRoleIfRequested() async {
    if (!enabled || testRole.isEmpty) return;
    if (kReleaseMode) {
      throw StateError('Automatic test sign-in is forbidden in release builds.');
    }
    final credentials = _testCredentials[testRole];
    if (credentials == null) {
      throw ArgumentError.value(
        testRole,
        'VOLTRIKE_TEST_ROLE',
        'Use passenger or driver.',
      );
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.email == credentials.email) return;
    if (currentUser != null) await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: credentials.email,
      password: credentials.password,
    );
  }

  static const Map<String, _TestCredentials> _testCredentials = {
    'passenger': _TestCredentials(
      'passenger@voltrike.test',
      'VolTrike123!',
    ),
    'driver': _TestCredentials(
      'driver@voltrike.test',
      'VolTrike123!',
    ),
  };
}

class _TestCredentials {
  const _TestCredentials(this.email, this.password);

  final String email;
  final String password;
}
