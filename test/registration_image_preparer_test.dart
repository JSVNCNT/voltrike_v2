import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
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
}
