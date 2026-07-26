import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'config/firebase_emulator_config.dart';
import 'config/firebase_options.dart';
import 'features/common/services/notification_service.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      // Flutter bindings and runApp must use the same zone.
      WidgetsFlutterBinding.ensureInitialized();

      // Handle Flutter framework errors.
      FlutterError.onError = FlutterError.presentError;

      // Initialize either the connected project or the explicitly requested
      // demo project. Demo mode is fail-closed and has no live resources.
      await Firebase.initializeApp(
        options: FirebaseEmulatorConfig.enabled
            ? FirebaseEmulatorConfig.firebaseOptions
            : DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseEmulatorConfig.connect();
      await FirebaseEmulatorConfig.signInTestRoleIfRequested();
      if (!FirebaseEmulatorConfig.enabled) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        await NotificationService.instance.initialize();
      }

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
