// The LiveKit audio-session API is marked experimental upstream. We use its
// documented communication preset because Android must receive voice-call
// attributes before WebRTC creates the audio device.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import 'app/app.dart';
import 'config/firebase_emulator_config.dart';
import 'config/firebase_options.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference_store.dart';
import 'features/common/services/notification_service.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      // Flutter bindings and runApp must use the same zone.
      WidgetsFlutterBinding.ensureInitialized();

      // Configure WebRTC for two-way speech before a call can initialise its
      // audio device. This gives Android the voice-communication audio
      // attributes required by its echo-cancellation path, rather than normal
      // media playback routing.
      await LiveKitClient.initialize(
        initialAudioSessionOptions: const AudioSessionOptions.communication(),
      );

      ThemePreferenceStore themePreferenceStore;
      try {
        themePreferenceStore =
            await SharedPreferencesThemePreferenceStore.create();
      } catch (error) {
        debugPrint('Theme preferences unavailable: $error');
        themePreferenceStore = MemoryThemePreferenceStore();
      }

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
      await _activateAppCheck();
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

      // Configure the system UI for the first frame. The app and light-only
      // public routes keep it synchronized after startup.
      SystemChrome.setSystemUIOverlayStyle(
        AppTheme.systemUiOverlayStyleFor(themePreferenceStore.read()),
      );

      runApp(
        ProviderScope(
          overrides: [
            themePreferenceStoreProvider.overrideWithValue(
              themePreferenceStore,
            ),
          ],
          child: const VolTrikeApp(),
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

Future<void> _activateAppCheck() async {
  if (FirebaseEmulatorConfig.enabled) return;
  if (kIsWeb) {
    const siteKey = String.fromEnvironment('FIREBASE_APP_CHECK_WEB_SITE_KEY');
    if (siteKey.isEmpty) {
      throw StateError(
        'FIREBASE_APP_CHECK_WEB_SITE_KEY is required for a production web build.',
      );
    }
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(siteKey),
    );
    return;
  }
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
}
