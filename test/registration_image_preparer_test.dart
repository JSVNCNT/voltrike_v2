import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:voltrike_v2/core/native/registration_image_bridge_contract.dart';
import 'package:voltrike_v2/features/auth/services/registration_image_preparer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'voltrike-registration-image-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('prepares a picked image through an isolate-safe request', () async {
    final source = File('${temporaryDirectory.path}/landscape.jpg');
    final image = image_lib.Image(width: 1200, height: 600);
    await source.writeAsBytes(image_lib.encodeJpg(image, quality: 90));

    final prepared = await const RegistrationImagePreparer().prepare(
      sourcePath: source.path,
      targetAspectRatio: 1,
      targetWidth: 720,
    );

    expect(await prepared.exists(), isTrue);
    expect(await prepared.length(), greaterThan(0));
    expect(
      await prepared.length(),
      lessThanOrEqualTo(registrationImageMaxBytes),
    );

    final decoded = image_lib.decodeJpg(await prepared.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, 600);
    expect(decoded.height, 600);
  });

  test('crops portrait documents to the requested A-series ratio', () async {
    final source = File('${temporaryDirectory.path}/document.png');
    final image = image_lib.Image(width: 1000, height: 1800);
    await source.writeAsBytes(image_lib.encodePng(image));

    final result = prepareRegistrationImageInBackground(<String, Object>{
      'sourcePath': source.path,
      'targetAspectRatio': 1 / 1.414,
      'targetWidth': 700,
    });

    expect(result['error'], isNull);
    final outputPath = result['outputPath'];
    expect(outputPath, isA<String>());

    final decoded = image_lib.decodeJpg(
      await File(outputPath! as String).readAsBytes(),
    );
    expect(decoded, isNotNull);
    expect(decoded!.width, 700);
    expect(decoded.width / decoded.height, closeTo(1 / 1.414, 0.002));
  });

  test('returns a useful error for unreadable gallery content', () async {
    final source = File('${temporaryDirectory.path}/not-an-image.bin');
    await source.writeAsString('not an image');

    final result = prepareRegistrationImageInBackground(<String, Object>{
      'sourcePath': source.path,
      'targetAspectRatio': 1,
      'targetWidth': 1080,
    });

    expect(result['error'], contains('Use a JPG, PNG, or take a new photo'));
    expect(result['outputPath'], isNull);
  });

  test('auto mode uses the native file path when it succeeds', () async {
    final source = File('${temporaryDirectory.path}/native.jpg');
    await source.writeAsBytes(<int>[1, 2, 3]);
    final preparedBytes = image_lib.encodeJpg(
      image_lib.Image(width: 600, height: 600),
    );
    final bridge = _FakeNativeImageBridge(
      onPrepare: (request) async {
        await File(request.outputPath).writeAsBytes(preparedBytes);
        return NativeRegistrationImageResult(
          status: NativeRegistrationImageStatus.ok,
          outputPath: request.outputPath,
          outputWidth: 600,
          outputHeight: 600,
          outputBytes: preparedBytes.length,
        );
      },
    );

    final output = await RegistrationImagePreparer(
      nativeBridge: bridge,
    ).prepare(sourcePath: source.path, targetAspectRatio: 1, targetWidth: 1080);

    expect(bridge.calls, 1);
    expect(await output.readAsBytes(), preparedBytes);
  });

  test('native transport failure immediately falls back to Dart', () async {
    final source = File('${temporaryDirectory.path}/fallback.jpg');
    final image = image_lib.Image(width: 1200, height: 600);
    await source.writeAsBytes(image_lib.encodeJpg(image, quality: 90));
    final bridge = _FakeNativeImageBridge(
      onPrepare: (_) async => throw StateError('bridge unavailable'),
    );

    final output = await RegistrationImagePreparer(
      nativeBridge: bridge,
    ).prepare(sourcePath: source.path, targetAspectRatio: 1, targetWidth: 720);

    expect(bridge.calls, 1);
    final decoded = image_lib.decodeJpg(await output.readAsBytes());
    expect(decoded, isNotNull);
    expect((decoded!.width, decoded.height), (600, 600));
  });

  test('native safety rejection is terminal and never runs Dart', () async {
    final source = File('${temporaryDirectory.path}/too-large.jpg');
    await source.writeAsBytes(<int>[1, 2, 3]);
    final bridge = _FakeNativeImageBridge(
      onPrepare: (_) async => const NativeRegistrationImageResult(
        status: NativeRegistrationImageStatus.decodeLimitExceeded,
      ),
    );

    await expectLater(
      RegistrationImagePreparer(nativeBridge: bridge).prepare(
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

    expect(bridge.calls, 1);
    expect(bridge.lastRequest, isNotNull);
    expect(await File(bridge.lastRequest!.outputPath).exists(), isFalse);
  });

  test('rejects and removes corrupt native output', () async {
    final source = File('${temporaryDirectory.path}/corrupt.jpg');
    await source.writeAsBytes(<int>[1, 2, 3]);
    final bridge = _FakeNativeImageBridge(
      onPrepare: (request) async {
        await File(request.outputPath).writeAsBytes(<int>[7, 8, 9]);
        return NativeRegistrationImageResult(
          status: NativeRegistrationImageStatus.ok,
          outputPath: request.outputPath,
          outputWidth: 600,
          outputHeight: 600,
          outputBytes: 3,
        );
      },
    );

    await expectLater(
      RegistrationImagePreparer(nativeBridge: bridge).prepare(
        sourcePath: source.path,
        targetAspectRatio: 1,
        targetWidth: 1080,
      ),
      throwsA(isA<RegistrationImagePreparationException>()),
    );

    expect(bridge.lastRequest, isNotNull);
    expect(await File(bridge.lastRequest!.outputPath).exists(), isFalse);
  });

  test('dart rollback mode never calls the native bridge', () async {
    final source = File('${temporaryDirectory.path}/rollback.jpg');
    final image = image_lib.Image(width: 1200, height: 600);
    await source.writeAsBytes(image_lib.encodeJpg(image, quality: 90));
    final bridge = _FakeNativeImageBridge(
      onPrepare: (_) async => throw StateError('must not be called'),
    );

    final output = await RegistrationImagePreparer(
      nativeBridge: bridge,
      engine: 'dart',
    ).prepare(sourcePath: source.path, targetAspectRatio: 1, targetWidth: 720);

    expect(bridge.calls, 0);
    expect(await output.exists(), isTrue);
  });
}

typedef _NativePrepare =
    Future<NativeRegistrationImageResult> Function(
      NativeRegistrationImageRequest request,
    );

class _FakeNativeImageBridge implements NativeRegistrationImageBridge {
  _FakeNativeImageBridge({required this.onPrepare});

  final _NativePrepare onPrepare;
  int calls = 0;
  NativeRegistrationImageRequest? lastRequest;

  @override
  bool get isSupported => true;

  @override
  Future<NativeRegistrationImageResult> prepare(
    NativeRegistrationImageRequest request,
  ) {
    calls++;
    lastRequest = request;
    return onPrepare(request);
  }
}
