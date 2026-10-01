import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:voltrike_v2/core/constants/app_assets.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';

/// Produces cached, branded marker bitmaps shared by ride maps.
class RideMarkerFactory {
  RideMarkerFactory._();

  static final Map<ui.Brightness, Future<BitmapDescriptor>> _driverMarkers = {};

  static Future<BitmapDescriptor> driverMarker({
    required ui.Brightness brightness,
  }) {
    return _driverMarkers.putIfAbsent(
      brightness,
      () => _buildDriverMarker(brightness),
    );
  }

  static Future<BitmapDescriptor> _buildDriverMarker(
    ui.Brightness brightness,
  ) async {
    // Google Maps renders marker bitmaps in screen pixels. Keep this asset
    // deliberately compact so it does not grow into a large map obstruction
    // on high-density Android displays.
    const size = 48.0;
    const padding = 2.0;
    const logoSize = size - padding * 2;
    final isDark = brightness == ui.Brightness.dark;
    final data = await rootBundle.load(
      isDark ? AppAssets.logoDark : AppAssets.logoLight,
    );
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: logoSize.toInt(),
      targetHeight: logoSize.toInt(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
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
      22,
      ui.Paint()
        ..color = isDark
            ? const ui.Color(0xFFFFFFFF)
            : const ui.Color(0xFF000000),
    );

    canvas.save();
    canvas.clipPath(
      ui.Path()
        ..addOval(const ui.Rect.fromLTWH(padding, padding, logoSize, logoSize)),
    );
    canvas.drawImageRect(
      frame.image,
      ui.Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      const ui.Rect.fromLTWH(padding, padding, logoSize, logoSize),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    picture.dispose();
    frame.image.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('Could not create driver marker bitmap.');
    }
    return BitmapDescriptor.bytes(bytes.buffer.asUint8List());
  }
}
