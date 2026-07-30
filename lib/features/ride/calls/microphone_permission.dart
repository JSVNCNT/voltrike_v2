import 'package:permission_handler/permission_handler.dart';

Future<void> ensureVoiceCallMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isGranted) return;
  throw StateError(
    status.isPermanentlyDenied
        ? 'Microphone access is disabled in system settings.'
        : 'Microphone permission is required for a voice call.',
  );
}
