import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

const int registrationImageMaxBytes = 4 * 1024 * 1024;

class RegistrationImagePreparationException implements Exception {
  const RegistrationImagePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RegistrationImagePreparer {
  const RegistrationImagePreparer();

  Future<File> prepare({
    required String sourcePath,
    required double targetAspectRatio,
    required int targetWidth,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() == 0) {
      throw const RegistrationImagePreparationException(
        'The selected image is no longer available. Please choose it again.',
      );
    }

    final result = await compute(
      prepareRegistrationImageInBackground,
      <String, Object>{
        'sourcePath': sourcePath,
        'targetAspectRatio': targetAspectRatio,
        'targetWidth': targetWidth,
      },
      debugLabel: 'prepare-registration-image',
    );

    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      throw RegistrationImagePreparationException(error);
    }

    final outputPath = result['outputPath'];
    if (outputPath is! String || outputPath.isEmpty) {
      throw const RegistrationImagePreparationException(
        'The image processor did not create a usable file. Please try again.',
      );
    }

    final output = File(outputPath);
    if (!await output.exists() || await output.length() == 0) {
      throw const RegistrationImagePreparationException(
        'The prepared image could not be saved. Please try again.',
      );
    }
    if (await output.length() > registrationImageMaxBytes) {
      throw const RegistrationImagePreparationException(
        'The prepared image is larger than 4 MB. Retake it with less '
        'background in the frame.',
      );
    }

    return output;
  }
}

/// Runs in a background isolate. Keep the request and response limited to
/// isolate-safe primitive values so Android picker objects are never captured.
@visibleForTesting
Map<String, Object?> prepareRegistrationImageInBackground(
  Map<String, Object> request,
) {
  try {
    final sourcePath = request['sourcePath'];
    final requestedAspectRatio = request['targetAspectRatio'];
    final targetWidth = request['targetWidth'];
    if (sourcePath is! String ||
        sourcePath.isEmpty ||
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

    final decoded = image_lib.decodeImage(source.readAsBytesSync());
    if (decoded == null) {
      return const <String, Object?>{
        'error':
            'That image format could not be read. Use a JPG, PNG, or take a '
            'new photo with the camera.',
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

    final output = File('$sourcePath.voltrike.jpg');
    output.writeAsBytesSync(encoded, flush: true);
    return <String, Object?>{'outputPath': output.path};
  } catch (_) {
    return const <String, Object?>{
      'error':
          'The image could not be processed. Try another image or retake it.',
    };
  }
}
