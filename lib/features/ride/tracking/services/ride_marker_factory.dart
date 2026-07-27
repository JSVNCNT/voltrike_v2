import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

/// Produces cached, branded marker bitmaps shared by ride maps.
class RideMarkerFactory {
  RideMarkerFactory._();

  static Future<BitmapDescriptor>? _driverMarker;

  static Future<BitmapDescriptor> driverMarker() {
    return _driverMarker ??= _buildDriverMarker();
  }

  static Future<BitmapDescriptor> _buildDriverMarker() async {
    // Google Maps renders marker bitmaps in screen pixels. Keep this asset
    // deliberately compact so it does not grow into a large map obstruction
    // on high-density Android displays.
    const size = 48.0;
    const padding = 8.0;
    final data = await rootBundle.load('assets/images/appLogo.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const center = ui.Offset(size / 2, size / 2);

    canvas.drawCircle(
      center,
      23,
      ui.Paint()..color = const ui.Color(0x33000000),
    );
    canvas.drawCircle(
      center,
      21,
      ui.Paint()..color = const ui.Color(0xFF008B8B),
    );
    canvas.drawCircle(
      center,
      19,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      17,
      ui.Paint()..color = const ui.Color(0xFF008B8B),
    );

    canvas.save();
    canvas.clipPath(
      ui.Path()..addOval(const ui.Rect.fromLTWH(padding, padding, 32, 32)),
    );
    canvas.drawImageRect(
      frame.image,
      ui.Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      const ui.Rect.fromLTWH(padding, padding, 32, 32),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final image = await recorder.endRecording().toImage(48, 48);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Could not create driver marker bitmap.');
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }
}
