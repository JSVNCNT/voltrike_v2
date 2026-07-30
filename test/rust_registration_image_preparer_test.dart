import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/native/registration_image_bridge_contract.dart';
import 'package:voltrike_v2/features/auth/services/registration_image_preparer.dart';
import 'package:voltrike_v2/features/auth/services/rust_registration_image_preparer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'voltrike-rust-registration-image-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'passes only file paths and transform settings to the native bridge',
    () async {
      final source = File('${temporaryDirectory.path}/picked.jpg');
      await source.writeAsBytes(<int>[1, 2, 3]);
      final outputPath = '${source.path}.voltrike.jpg';
      final bridge = _FakeRegistrationImageBridge(
        onPrepare: (request) async {
          await File(request.outputPath).writeAsBytes(<int>[4, 5, 6]);
          return NativeRegistrationImageResult(
            status: NativeRegistrationImageStatus.ok,
            outputPath: request.outputPath,
            sourceWidth: 1200,
            sourceHeight: 600,
            outputWidth: 600,
            outputHeight: 600,
            outputBytes: 3,
          );
        },
      );

      final output = await RustRegistrationImagePreparer(bridge: bridge)
          .prepare(
            sourcePath: source.path,
            targetAspectRatio: 1,
            targetWidth: 720,
          );

      expect(output.path, outputPath);
      expect(bridge.lastRequest?.sourcePath, source.path);
      expect(bridge.lastRequest?.outputPath, outputPath);
      expect(bridge.lastRequest?.targetAspectRatio, 1);
      expect(bridge.lastRequest?.targetWidth, 720);
    },
  );

  test('maps a native decode limit to a stable safe-size message', () async {
    final source = File('${temporaryDirectory.path}/oversized.jpg');
    await source.writeAsBytes(<int>[1]);
    final bridge = _FakeRegistrationImageBridge(
      onPrepare: (_) async => const NativeRegistrationImageResult(
        status: NativeRegistrationImageStatus.decodeLimitExceeded,
        diagnostic: 'source contains 9000000 pixels',
      ),
    );

    await expectLater(
      RustRegistrationImagePreparer(bridge: bridge).prepare(
        sourcePath: source.path,
        targetAspectRatio: 1,
        targetWidth: 1080,
      ),
      throwsA(
        isA<RegistrationImagePreparationException>().having(
          (error) => error.message,
          'message',
          contains('too large to process safely'),
        ),
      ),
    );
  });

  test(
    'rejects a native success that did not create the requested output',
    () async {
      final source = File('${temporaryDirectory.path}/picked.png');
      await source.writeAsBytes(<int>[1]);
      final bridge = _FakeRegistrationImageBridge(
        onPrepare: (request) async => NativeRegistrationImageResult(
          status: NativeRegistrationImageStatus.ok,
          outputPath: request.outputPath,
        ),
      );

      await expectLater(
        RustRegistrationImagePreparer(bridge: bridge).prepare(
          sourcePath: source.path,
          targetAspectRatio: 4 / 3,
          targetWidth: 1600,
        ),
        throwsA(
          isA<RegistrationImagePreparationException>().having(
            (error) => error.message,
            'message',
            contains('could not be saved'),
          ),
        ),
      );
    },
  );
}

typedef _PrepareCallback =
    Future<NativeRegistrationImageResult> Function(
      NativeRegistrationImageRequest request,
    );

class _FakeRegistrationImageBridge implements NativeRegistrationImageBridge {
  _FakeRegistrationImageBridge({required this.onPrepare});

  final _PrepareCallback onPrepare;
  NativeRegistrationImageRequest? lastRequest;

  @override
  bool get isSupported => true;

  @override
  Future<NativeRegistrationImageResult> prepare(
    NativeRegistrationImageRequest request,
  ) {
    lastRequest = request;
    return onPrepare(request);
  }
}
