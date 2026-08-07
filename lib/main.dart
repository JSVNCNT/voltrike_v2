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
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'config/firebase_emulator_config.dart';
import 'config/firebase_options.dart';
import 'core/config/mobile_security_config.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference_store.dart';
import 'features/common/services/notification_service.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      await SentryFlutter.init((options) {
        options
          ..dsn = const String.fromEnvironment('SENTRY_DSN')
          ..environment = const String.fromEnvironment(
            'SENTRY_ENVIRONMENT',
            defaultValue: 'development',
          )
          ..sendDefaultPii = false
          ..attachScreenshot = false
          ..attachViewHierarchy = false
          ..tracesSampleRate = _sentryTracesSampleRate();
        const release = String.fromEnvironment('SENTRY_RELEASE');
        if (release.isNotEmpty) options.release = release;
      }, appRunner: _bootstrap);
    },
    (error, stackTrace) {
      debugPrint('Unhandled Error: $error');
      debugPrintStack(stackTrace: stackTrace);
      unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    },
  );
}

double _sentryTracesSampleRate() {
  const configured = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '0.05',
  );
  final parsed = double.tryParse(configured);
  return parsed == null ? 0.05 : parsed.clamp(0, 1).toDouble();
}

Future<void> _bootstrap() async {
  // Flutter bindings and runApp must use the same zone.
  WidgetsFlutterBinding.ensureInitialized();

  ThemePreferenceStore themePreferenceStore;
  try {
    themePreferenceStore = await SharedPreferencesThemePreferenceStore.create();
  } catch (error) {
    debugPrint('Theme preferences unavailable: $error');
    themePreferenceStore = MemoryThemePreferenceStore();
  }

  // Handle Flutter framework errors.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      Sentry.captureException(details.exception, stackTrace: details.stack),
    );
  };

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
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Lock the application to portrait mode only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Configure the system UI for the first frame. The app and light-only
  // public routes keep it synchronized after startup.
  SystemChrome.setSystemUIOverlayStyle(
    AppTheme.systemUiOverlayStyleFor(themePreferenceStore.read()),
  );

  runApp(
    ProviderScope(
      overrides: [
        themePreferenceStoreProvider.overrideWithValue(themePreferenceStore),
      ],
      child: const VolTrikeApp(),
    ),
  );
  unawaited(_initializeOptionalServices());
}

Future<void> _initializeOptionalServices() async {
  // These capabilities should not delay the first usable frame. Each service
  // reports its own failure and can recover on the next app start.
  try {
    await LiveKitClient.initialize(
      initialAudioSessionOptions: const AudioSessionOptions.communication(),
    );
  } catch (error) {
    debugPrint('Voice-call audio initialization unavailable: $error');
  }
  if (!FirebaseEmulatorConfig.enabled) {
    try {
      await NotificationService.instance.initialize();
    } catch (error) {
      debugPrint('Push notification initialization unavailable: $error');
    }
  }
}

Future<void> _activateAppCheck() async {
  if (FirebaseEmulatorConfig.enabled) return;
  if (!MobileSecurityConfig.enableAppCheck) return;
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
