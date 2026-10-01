import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:voltrike_v2/features/ride/tracking/services/ride_marker_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in ui.Brightness.values) {
    test(
      'driver marker has a contrasting logo in ${brightness.name} mode',
      () async {
        final marker = await RideMarkerFactory.driverMarker(
          brightness: brightness,
        );
        final bitmap = image.decodePng(marker.byteData!)!;
        final isDark = brightness == ui.Brightness.dark;

        expect(bitmap.width, 48);
        expect(bitmap.height, 48);
        expect(bitmap.getPixel(0, 0).a, 0);

        // The space above the logo must show the circle, not an opaque
        // rectangular background from the asset.
        final background = bitmap.getPixel(24, 6);
        final expectedChannel = isDark ? 255 : 0;
        expect(background.r, expectedChannel);
        expect(background.g, expectedChannel);
        expect(background.b, expectedChannel);
        expect(background.a, 255);

        // Verify that the actual asset remains visible against the circle.
        var contrastingPixels = 0;
        for (var y = 12; y < 36; y++) {
          for (var x = 12; x < 36; x++) {
            final pixel = bitmap.getPixel(x, y);
            if (pixel.a == 255 && (isDark ? pixel.r < 128 : pixel.r > 128)) {
              contrastingPixels++;
            }
          }
        }
        expect(contrastingPixels, greaterThan(50));
      },
    );
  }

  test('switching themes uses distinct cached map icons', () async {
    final light = await RideMarkerFactory.driverMarker(
      brightness: ui.Brightness.light,
    );
    final dark = await RideMarkerFactory.driverMarker(
      brightness: ui.Brightness.dark,
    );
    expect(light, isNot(dark));
    expect(
      await RideMarkerFactory.driverMarker(brightness: ui.Brightness.light),
      same(light),
    );
  });
}
