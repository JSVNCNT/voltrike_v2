import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

Future<void> ensureVoiceCallMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (!status.isGranted) {
    throw StateError(
      status.isPermanentlyDenied
          ? 'Microphone access is disabled in system settings.'
          : 'Microphone permission is required for a voice call.',
    );
  }
  await _requestBluetoothAudioPermission();
}

Future<void> _requestBluetoothAudioPermission() async {
  if (!Platform.isAndroid) return;
  try {
    final status = await Permission.bluetoothConnect.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.bluetoothConnect.request();
    }
  } catch (_) {
    // Bluetooth headset routing is optional. The call can use the earpiece or
    // the explicit speaker control when this platform permission is absent.
  }
}
