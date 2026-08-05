import 'generated/api/registration_image.dart' as image_api;
import 'native_rust_platform.dart';
import 'registration_image_bridge_contract.dart';
import 'rust_bridge_runtime.dart';

NativeRegistrationImageBridge createNativeRegistrationImageBridge() =>
    GeneratedNativeRegistrationImageBridge();

class GeneratedNativeRegistrationImageBridge
    implements NativeRegistrationImageBridge {
  @override
  bool get isSupported => supportsNativeRust;

  @override
  Future<NativeRegistrationImageResult> prepare(
    NativeRegistrationImageRequest request,
  ) async {
    if (!isSupported) {
      throw UnsupportedError(
        'The VolTrike Rust image bridge is unavailable on this platform.',
      );
    }
    await RustBridgeRuntime.ensureInitialized();
    final result = await image_api.prepareRegistrationImageFile(
      sourcePath: request.sourcePath,
      outputPath: request.outputPath,
      targetAspectRatio: request.targetAspectRatio,
      targetWidth: request.targetWidth,
    );
    return NativeRegistrationImageResult(
      status: _status(result.status),
      outputPath: result.outputPath,
      sourceWidth: result.sourceWidth,
      sourceHeight: result.sourceHeight,
      outputWidth: result.outputWidth,
      outputHeight: result.outputHeight,
      outputBytes: _int(result.outputBytes, 'output bytes'),
      orientationApplied: result.orientationApplied,
      usedSizeRetry: result.usedSizeRetry,
      decodeMicros: _int(result.decodeMicros, 'decode time'),
      transformMicros: _int(result.transformMicros, 'transform time'),
      encodeMicros: _int(result.encodeMicros, 'encode time'),
      totalMicros: _int(result.totalMicros, 'total time'),
      diagnostic: result.diagnostic,
    );
  }

  static int _int(BigInt value, String fieldName) {
    if (value.isNegative || !value.isValidInt) {
      throw StateError('Rust returned invalid $fieldName.');
    }
    return value.toInt();
  }

  static NativeRegistrationImageStatus _status(
    image_api.RegistrationImageStatus status,
  ) {
    return switch (status) {
      image_api.RegistrationImageStatus.ok => NativeRegistrationImageStatus.ok,
      image_api.RegistrationImageStatus.invalidRequest =>
        NativeRegistrationImageStatus.invalidRequest,
      image_api.RegistrationImageStatus.sourceUnavailable =>
        NativeRegistrationImageStatus.sourceUnavailable,
      image_api.RegistrationImageStatus.sourceTooLarge =>
        NativeRegistrationImageStatus.sourceTooLarge,
      image_api.RegistrationImageStatus.unsupportedFormat =>
        NativeRegistrationImageStatus.unsupportedFormat,
      image_api.RegistrationImageStatus.decodeLimitExceeded =>
        NativeRegistrationImageStatus.decodeLimitExceeded,
      image_api.RegistrationImageStatus.decodeFailed =>
        NativeRegistrationImageStatus.decodeFailed,
      image_api.RegistrationImageStatus.encodeFailed =>
        NativeRegistrationImageStatus.encodeFailed,
      image_api.RegistrationImageStatus.outputTooLarge =>
        NativeRegistrationImageStatus.outputTooLarge,
      image_api.RegistrationImageStatus.writeFailed =>
        NativeRegistrationImageStatus.writeFailed,
      image_api.RegistrationImageStatus.nativePanic =>
        NativeRegistrationImageStatus.nativePanic,
    };
  }
}
