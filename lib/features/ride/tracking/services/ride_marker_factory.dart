import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Produces cached, branded marker bitmaps shared by ride maps.
class RideMarkerFactory {
  RideMarkerFactory._();

  static Future<BitmapDescriptor>? _driverMarker;

  static Future<BitmapDescriptor> driverMarker() {
    return _driverMarker ??= _buildDriverMarker();
  }

  static Future<BitmapDescriptor> _buildDriverMarker() async {
    const size = 112.0;
    const padding = 18.0;
    final data = await rootBundle.load('assets/images/appLogo.png');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 72,
      targetHeight: 72,
    );
    final frame = await codec.getNextFrame();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const center = ui.Offset(size / 2, size / 2);

    canvas.drawCircle(
      center,
      52,
      ui.Paint()..color = const ui.Color(0x33000000),
    );
    canvas.drawCircle(
      center,
      48,
      ui.Paint()..color = const ui.Color(0xFF008B8B),
    );
    canvas.drawCircle(
      center,
      44,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      40,
      ui.Paint()..color = const ui.Color(0xFF008B8B),
    );

    canvas.save();
    canvas.clipPath(
      ui.Path()..addOval(const ui.Rect.fromLTWH(padding, padding, 76, 76)),
    );
    canvas.drawImageRect(
      frame.image,
      ui.Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      const ui.Rect.fromLTWH(padding, padding, 76, 76),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final image = await recorder.endRecording().toImage(112, 112);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Could not create driver marker bitmap.');
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }
}
