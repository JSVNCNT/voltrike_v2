import 'dart:io';

import '../../../core/native/registration_image_bridge_contract.dart';
import 'registration_image_preparer.dart';

/// File-to-file adapter for the experimental Rust registration image backend.
///
/// The generated flutter_rust_bridge adapter will implement
/// [NativeRegistrationImageBridge]. Keeping that generated dependency outside
/// this class makes validation and user-facing error parity independently
/// testable.
class RustRegistrationImagePreparer {
  const RustRegistrationImagePreparer({required this.bridge});

  final NativeRegistrationImageBridge bridge;

  Future<File> prepare({
    required String sourcePath,
    required double targetAspectRatio,
    required int targetWidth,
    String? outputPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() == 0) {
      throw const RegistrationImagePreparationException(
        'The selected image is no longer available. Please choose it again.',
      );
    }
    if (!bridge.isSupported) {
      throw const RegistrationImagePreparationException(
        'The image processor is unavailable on this device. Please try again.',
      );
    }

    final requestedOutputPath = outputPath ?? '$sourcePath.voltrike.jpg';
    final result = await bridge.prepare(
      NativeRegistrationImageRequest(
        sourcePath: sourcePath,
        outputPath: requestedOutputPath,
        targetAspectRatio: targetAspectRatio,
        targetWidth: targetWidth,
      ),
    );
    if (result.status != NativeRegistrationImageStatus.ok) {
      throw RegistrationImagePreparationException(
        registrationImageMessageForNativeStatus(result.status),
      );
    }
    if (result.outputPath != requestedOutputPath) {
      throw const RegistrationImagePreparationException(
        'The image processor returned an unexpected file. Please try again.',
      );
    }

    final output = File(requestedOutputPath);
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
