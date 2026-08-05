import 'dart:io';

/// Rust is available on native Flutter targets. The calling adapters retain a
/// Dart fallback when a platform artifact has not been packaged yet.
bool get supportsNativeRust =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isWindows ||
    Platform.isLinux;
