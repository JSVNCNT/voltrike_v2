class NativeRegistrationImageRequest {
  const NativeRegistrationImageRequest({
    required this.sourcePath,
    required this.outputPath,
    required this.targetAspectRatio,
    required this.targetWidth,
  });

  final String sourcePath;
  final String outputPath;
  final double targetAspectRatio;
  final int targetWidth;
}

enum NativeRegistrationImageStatus {
  ok,
  invalidRequest,
  sourceUnavailable,
  sourceTooLarge,
  unsupportedFormat,
  decodeLimitExceeded,
  decodeFailed,
  encodeFailed,
  outputTooLarge,
  writeFailed,
  nativePanic,
}

class NativeRegistrationImageResult {
  const NativeRegistrationImageResult({
    required this.status,
    this.outputPath,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.outputWidth = 0,
    this.outputHeight = 0,
    this.outputBytes = 0,
    this.orientationApplied = false,
    this.usedSizeRetry = false,
    this.decodeMicros = 0,
    this.transformMicros = 0,
    this.encodeMicros = 0,
    this.totalMicros = 0,
    this.diagnostic,
  });

  final NativeRegistrationImageStatus status;
  final String? outputPath;
  final int sourceWidth;
  final int sourceHeight;
  final int outputWidth;
  final int outputHeight;
  final int outputBytes;
  final bool orientationApplied;
  final bool usedSizeRetry;
  final int decodeMicros;
  final int transformMicros;
  final int encodeMicros;
  final int totalMicros;
  final String? diagnostic;
}

abstract interface class NativeRegistrationImageBridge {
  bool get isSupported;

  Future<NativeRegistrationImageResult> prepare(
    NativeRegistrationImageRequest request,
  );
}
