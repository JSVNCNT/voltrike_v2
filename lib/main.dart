import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'config/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle Flutter framework errors.
  FlutterError.onError = FlutterError.presentError;

  await runZonedGuarded(
    () async {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Lock the application to portrait mode only.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // Configure the system UI.
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      runApp(
        const ProviderScope(
          child: VolTrikeApp(),
        ),
      );
    },
    (error, stackTrace) {
      debugPrint('Unhandled Error: $error');
      debugPrintStack(stackTrace: stackTrace);

      // Future:
      // FirebaseCrashlytics.instance.recordError(error, stackTrace);
    },
  );
}