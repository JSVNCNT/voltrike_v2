import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

import '../../../core/native/registration_image_bridge.dart';

const int registrationImageMaxBytes = 4 * 1024 * 1024;
const int registrationImageMaxSourceBytes = 32 * 1024 * 1024;
const int registrationImageMaxSourceDimension = 4096;
const int registrationImageMaxSourcePixels = 8 * 1000 * 1000;
const String registrationImageEngineEnvironmentKey = 'VOLTRIKE_IMAGE_ENGINE';

class RegistrationImagePreparationException implements Exception {
  const RegistrationImagePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RegistrationImagePreparer {
  const RegistrationImagePreparer({
    this.nativeBridge,
    this.engine = const String.fromEnvironment(
      registrationImageEngineEnvironmentKey,
      defaultValue: 'auto',
    ),
  });

  /// `auto` uses Rust where supported, `dart` is the rollback path, and
  /// `rust` explicitly requests native-first behavior with the same fallback.
  final String engine;
  final NativeRegistrationImageBridge? nativeBridge;
  static int _nextOutputId = 0;

  Future<File> prepare({
    required String sourcePath,
    required double targetAspectRatio,
    required int targetWidth,
    String? outputPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const RegistrationImagePreparationException(
        'The selected image is no longer available. Please choose it again.',
      );
    }
    final sourceBytes = await source.length();
    if (sourceBytes == 0) {
      throw const RegistrationImagePreparationException(
        'The selected image is no longer available. Please choose it again.',
      );
    }
    if (sourceBytes > registrationImageMaxSourceBytes) {
      throw const RegistrationImagePreparationException(
        'That image is too large to process safely. Choose a smaller image or '
        'retake it.',
      );
    }
    final requestedOutputPath =
        outputPath ??
        '$sourcePath.${DateTime.now().microsecondsSinceEpoch}-'
            '${_nextOutputId++}.voltrike.jpg';

    final bridge = nativeBridge ?? createNativeRegistrationImageBridge();
    if (_shouldUseNative(bridge)) {
      try {
        return await _prepareNative(
          bridge: bridge,
          sourcePath: sourcePath,
          outputPath: requestedOutputPath,
          targetAspectRatio: targetAspectRatio,
          targetWidth: targetWidth,
        );
      } on RegistrationImagePreparationException {
        rethrow;
      } catch (_) {
        await _discardOutput(requestedOutputPath);
        debugPrint(
          'Rust registration image unavailable; using the Dart fallback.',
        );
      }
    }

    final result = await compute(
      prepareRegistrationImageInBackground,
      <String, Object>{
        'sourcePath': sourcePath,
        'outputPath': requestedOutputPath,
        'targetAspectRatio': targetAspectRatio,
        'targetWidth': targetWidth,
      },
      debugLabel: 'prepare-registration-image',
    );

    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      throw RegistrationImagePreparationException(error);
    }

    final preparedOutputPath = result['outputPath'];
    if (preparedOutputPath is! String || preparedOutputPath.isEmpty) {
      throw const RegistrationImagePreparationException(
        'The image processor did not create a usable file. Please try again.',
      );
    }

    return _validateOutput(preparedOutputPath);
  }

  bool _shouldUseNative(NativeRegistrationImageBridge bridge) {
    final selected = engine.trim().toLowerCase();
    return bridge.isSupported && (selected == 'auto' || selected == 'rust');
  }

  Future<File> _prepareNative({
    required NativeRegistrationImageBridge bridge,
    required String sourcePath,
    required String outputPath,
    required double targetAspectRatio,
    required int targetWidth,
  }) async {
    final result = await bridge.prepare(
      NativeRegistrationImageRequest(
        sourcePath: sourcePath,
        outputPath: outputPath,
        targetAspectRatio: targetAspectRatio,
        targetWidth: targetWidth,
      ),
    );
    if (result.status != NativeRegistrationImageStatus.ok) {
      await _discardOutput(outputPath);
      throw RegistrationImagePreparationException(
        registrationImageMessageForNativeStatus(result.status),
      );
    }
    if (result.outputPath != outputPath ||
        result.outputBytes <= 0 ||
        result.outputBytes > registrationImageMaxBytes ||
        result.outputWidth <= 0 ||
        result.outputHeight <= 0 ||
        result.outputWidth > targetWidth ||
        ((result.outputWidth / result.outputHeight) - targetAspectRatio).abs() >
            0.02) {
      await _discardOutput(outputPath);
      throw const RegistrationImagePreparationException(
        'The image processor returned an invalid file. Please try again.',
      );
    }
    return _validateOutput(outputPath, expectedBytes: result.outputBytes);
  }

  Future<File> _validateOutput(String outputPath, {int? expectedBytes}) async {
    final output = File(outputPath);
    if (!await output.exists() || await output.length() == 0) {
      throw const RegistrationImagePreparationException(
        'The prepared image could not be saved. Please try again.',
      );
    }
    final outputBytes = await output.length();
    if (expectedBytes != null && outputBytes != expectedBytes) {
      await _discardOutput(outputPath);
      throw const RegistrationImagePreparationException(
        'The image processor returned an invalid file. Please try again.',
      );
    }
    if (outputBytes > registrationImageMaxBytes) {
      await _discardOutput(outputPath);
      throw const RegistrationImagePreparationException(
        'The prepared image is larger than 4 MB. Retake it with less '
        'background in the frame.',
      );
    }
    if (!await _hasJpegMarkers(output, outputBytes)) {
      await _discardOutput(outputPath);
      throw const RegistrationImagePreparationException(
        'The image processor returned an invalid file. Please try again.',
      );
    }

    return output;
  }

  Future<bool> _hasJpegMarkers(File output, int outputBytes) async {
    if (outputBytes < 5) return false;
    RandomAccessFile? handle;
    try {
      handle = await output.open();
      final header = await handle.read(3);
      await handle.setPosition(outputBytes - 2);
      final footer = await handle.read(2);
      return header.length == 3 &&
          header[0] == 0xff &&
          header[1] == 0xd8 &&
          header[2] == 0xff &&
          footer.length == 2 &&
          footer[0] == 0xff &&
          footer[1] == 0xd9;
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  Future<void> _discardOutput(String outputPath) async {
    try {
      final output = File(outputPath);
      if (await output.exists()) {
        await output.delete();
      }
    } catch (_) {
      // Best-effort cleanup must not replace the stable preparation error.
    }
  }
}

String registrationImageMessageForNativeStatus(
  NativeRegistrationImageStatus status,
) {
  return switch (status) {
    NativeRegistrationImageStatus.invalidRequest =>
      'The image preparation settings are invalid. Please try again.',
    NativeRegistrationImageStatus.sourceUnavailable =>
      'The selected image is no longer available. Please choose it again.',
    NativeRegistrationImageStatus.sourceTooLarge ||
    NativeRegistrationImageStatus.decodeLimitExceeded =>
      'That image is too large to process safely. Choose a smaller image or '
          'retake it.',
    NativeRegistrationImageStatus.unsupportedFormat ||
    NativeRegistrationImageStatus.decodeFailed =>
      'That image format could not be read. Use a JPG, PNG, or take a new '
          'photo with the camera.',
    NativeRegistrationImageStatus.outputTooLarge =>
      'The prepared image is larger than 4 MB. Retake it with less '
          'background in the frame.',
    NativeRegistrationImageStatus.encodeFailed ||
    NativeRegistrationImageStatus.writeFailed ||
    NativeRegistrationImageStatus.nativePanic ||
    NativeRegistrationImageStatus.ok =>
      'The image could not be processed. Try another image or retake it.',
  };
}

/// Runs in a background isolate. Keep the request and response limited to
/// isolate-safe primitive values so Android picker objects are never captured.
@visibleForTesting
Map<String, Object?> prepareRegistrationImageInBackground(
  Map<String, Object> request,
) {
  try {
    final sourcePath = request['sourcePath'];
    final requestedOutputPath = request['outputPath'];
    final requestedAspectRatio = request['targetAspectRatio'];
    final targetWidth = request['targetWidth'];
    if (sourcePath is! String ||
        sourcePath.isEmpty ||
        (requestedOutputPath != null &&
            (requestedOutputPath is! String ||
                requestedOutputPath.isEmpty ||
                requestedOutputPath == sourcePath)) ||
        requestedAspectRatio is! num ||
        !requestedAspectRatio.isFinite ||
        requestedAspectRatio <= 0 ||
        targetWidth is! int ||
        targetWidth <= 0) {
      return const <String, Object?>{
        'error':
            'The image preparation settings are invalid. Please try again.',
      };
    }
    final targetAspectRatio = requestedAspectRatio.toDouble();

    final source = File(sourcePath);
    if (!source.existsSync() || source.lengthSync() == 0) {
      return const <String, Object?>{
        'error':
            'The selected image is no longer available. Please choose it again.',
      };
    }
    if (source.lengthSync() > registrationImageMaxSourceBytes) {
      return const <String, Object?>{
        'error':
            'That image is too large to process safely. Choose a smaller image '
            'or retake it.',
      };
    }

    final decoded = image_lib.decodeImage(source.readAsBytesSync());
    if (decoded == null) {
      return const <String, Object?>{
        'error':
            'That image format could not be read. Use a JPG, PNG, or take a '
            'new photo with the camera.',
      };
    }
    final sourcePixels = decoded.width * decoded.height;
    if (decoded.width > registrationImageMaxSourceDimension ||
        decoded.height > registrationImageMaxSourceDimension ||
        sourcePixels > registrationImageMaxSourcePixels) {
      return const <String, Object?>{
        'error':
            'That image is too large to process safely. Choose a smaller image '
            'or retake it.',
      };
    }

    var prepared = image_lib.bakeOrientation(decoded);
    final currentRatio = prepared.width / prepared.height;
    if ((currentRatio - targetAspectRatio).abs() > 0.01) {
      if (currentRatio > targetAspectRatio) {
        final cropWidth = (prepared.height * targetAspectRatio).round().clamp(
          1,
          prepared.width,
        );
        prepared = image_lib.copyCrop(
          prepared,
          x: (prepared.width - cropWidth) ~/ 2,
          y: 0,
          width: cropWidth,
          height: prepared.height,
        );
      } else {
        final cropHeight = (prepared.width / targetAspectRatio).round().clamp(
          1,
          prepared.height,
        );
        prepared = image_lib.copyCrop(
          prepared,
          x: 0,
          y: (prepared.height - cropHeight) ~/ 2,
          width: prepared.width,
          height: cropHeight,
        );
      }
    }

    if (prepared.width > targetWidth) {
      prepared = image_lib.copyResize(prepared, width: targetWidth);
    }

    var encoded = image_lib.encodeJpg(prepared, quality: 78);
    if (encoded.length > 3 * 1024 * 1024 && prepared.width > 1000) {
      prepared = image_lib.copyResize(prepared, width: 1000);
      encoded = image_lib.encodeJpg(prepared, quality: 72);
    }
    if (encoded.isEmpty) {
      return const <String, Object?>{
        'error': 'The image could not be converted to JPG. Please try again.',
      };
    }
    if (encoded.length > registrationImageMaxBytes) {
      return const <String, Object?>{
        'error':
            'The prepared image is larger than 4 MB. Retake it with less '
            'background in the frame.',
      };
    }

    final outputPath = requestedOutputPath is String
        ? requestedOutputPath
        : '$sourcePath.voltrike.jpg';
    final output = File(outputPath);
    final temporaryOutput = File(
      '$outputPath.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      temporaryOutput.writeAsBytesSync(encoded, flush: true);
      try {
        temporaryOutput.renameSync(outputPath);
      } on FileSystemException {
        if (!output.existsSync()) rethrow;
        output.deleteSync();
        temporaryOutput.renameSync(outputPath);
      }
      return <String, Object?>{'outputPath': output.path};
    } finally {
      if (temporaryOutput.existsSync()) {
        temporaryOutput.deleteSync();
      }
    }
  } catch (_) {
    return const <String, Object?>{
      'error':
          'The image could not be processed. Try another image or retake it.',
    };
  }
}
