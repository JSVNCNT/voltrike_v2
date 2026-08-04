import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as navigation;

import '../theme/app_colors.dart';

/// App-owned geographic coordinate.
///
/// Keeping this type outside the provider SDK prevents bookings, repositories,
/// and routing services from depending on a beta map implementation.
@immutable
class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  navigation.LatLng toNavigation() =>
      navigation.LatLng(latitude: latitude, longitude: longitude);

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

@immutable
class CameraPosition {
  const CameraPosition({
    required this.target,
    this.zoom = 3,
    this.bearing = 0,
    this.tilt = 0,
  });

  final LatLng target;
  final double zoom;
  final double bearing;
  final double tilt;

  navigation.CameraPosition toNavigation() => navigation.CameraPosition(
    target: target.toNavigation(),
    zoom: zoom,
    bearing: bearing,
    tilt: tilt,
  );
}

@immutable
class CameraUpdate {
  const CameraUpdate._({required this.target, required this.zoom});

  factory CameraUpdate.newLatLngZoom(LatLng target, double zoom) =>
      CameraUpdate._(target: target, zoom: zoom);

  final LatLng target;
  final double zoom;

  navigation.CameraUpdate toNavigation() =>
      navigation.CameraUpdate.newLatLngZoom(target.toNavigation(), zoom);
}

@immutable
class MarkerId {
  const MarkerId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is MarkerId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class PolylineId {
  const PolylineId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is PolylineId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class PolygonId {
  const PolygonId(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is PolygonId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class InfoWindow {
  const InfoWindow({this.title, this.snippet});

  final String? title;
  final String? snippet;

  @override
  bool operator ==(Object other) =>
      other is InfoWindow && title == other.title && snippet == other.snippet;

  @override
  int get hashCode => Object.hash(title, snippet);
}

enum _BitmapDescriptorKind { defaultMarker, hue, bytes }

@immutable
class BitmapDescriptor {
  const BitmapDescriptor._(
    this._kind, {
    this.hue,
    this.byteData,
    this.cacheKey,
  });

  static const double hueRed = 0;
  static const double hueGreen = 120;
  static const double hueCyan = 180;
  static const double hueAzure = 210;

  static const BitmapDescriptor defaultMarker = BitmapDescriptor._(
    _BitmapDescriptorKind.defaultMarker,
  );

  factory BitmapDescriptor.defaultMarkerWithHue(double hue) =>
      BitmapDescriptor._(
        _BitmapDescriptorKind.hue,
        hue: hue,
        cacheKey: 'hue:$hue',
      );

  factory BitmapDescriptor.bytes(Uint8List bytes) => BitmapDescriptor._(
    _BitmapDescriptorKind.bytes,
    byteData: bytes,
    cacheKey:
        'bytes:${bytes.length}:${bytes.isEmpty ? 0 : bytes.first}:'
        '${bytes.isEmpty ? 0 : bytes.last}',
  );

  final _BitmapDescriptorKind _kind;
  final double? hue;
  final Uint8List? byteData;
  final String? cacheKey;

  @override
  bool operator ==(Object other) =>
      other is BitmapDescriptor &&
      _kind == other._kind &&
      hue == other.hue &&
      cacheKey == other.cacheKey;

  @override
  int get hashCode => Object.hash(_kind, hue, cacheKey);
}

@immutable
class Marker {
  const Marker({
    required this.markerId,
    required this.position,
    this.infoWindow = const InfoWindow(),
    this.icon = BitmapDescriptor.defaultMarker,
    this.anchor = const Offset(0.5, 1),
    this.rotation = 0,
    this.flat = false,
  });

  final MarkerId markerId;
  final LatLng position;
  final InfoWindow infoWindow;
  final BitmapDescriptor icon;
  final Offset anchor;
  final double rotation;
  final bool flat;

  @override
  bool operator ==(Object other) =>
      other is Marker &&
      markerId == other.markerId &&
      position == other.position &&
      infoWindow == other.infoWindow &&
      icon == other.icon &&
      anchor == other.anchor &&
      rotation == other.rotation &&
      flat == other.flat;

  @override
  int get hashCode =>
      Object.hash(markerId, position, infoWindow, icon, anchor, rotation, flat);
}

@immutable
class Polyline {
  const Polyline({
    required this.polylineId,
    required this.points,
    this.width = 10,
    this.color = AppColors.trafficRoute,
    this.geodesic = false,
    this.visible = true,
  });

  final PolylineId polylineId;
  final List<LatLng> points;
  final int width;
  final Color color;
  final bool geodesic;
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is Polyline &&
      polylineId == other.polylineId &&
      listEquals(points, other.points) &&
      width == other.width &&
      color == other.color &&
      geodesic == other.geodesic &&
      visible == other.visible;

  @override
  int get hashCode => Object.hash(
    polylineId,
    Object.hashAll(points),
    width,
    color,
    geodesic,
    visible,
  );
}

@immutable
class Polygon {
  const Polygon({
    required this.polygonId,
    required this.points,
    this.holes = const <List<LatLng>>[],
    this.fillColor = const Color(0x40EF4444),
    this.strokeColor = const Color(0xFFB91C1C),
    this.strokeWidth = 3,
    this.geodesic = false,
    this.visible = true,
    this.zIndex = 0,
  });

  final PolygonId polygonId;
  final List<LatLng> points;
  final List<List<LatLng>> holes;
  final Color fillColor;
  final Color strokeColor;
  final int strokeWidth;
  final bool geodesic;
  final bool visible;
  final double zIndex;

  @override
  bool operator ==(Object other) =>
      other is Polygon &&
      polygonId == other.polygonId &&
      listEquals(points, other.points) &&
      _listOfListsEquals(holes, other.holes) &&
      fillColor == other.fillColor &&
      strokeColor == other.strokeColor &&
      strokeWidth == other.strokeWidth &&
      geodesic == other.geodesic &&
      visible == other.visible &&
      zIndex == other.zIndex;

  @override
  int get hashCode => Object.hash(
    polygonId,
    Object.hashAll(points),
    Object.hashAll(holes.map(Object.hashAll)),
    fillColor,
    strokeColor,
    strokeWidth,
    geodesic,
    visible,
    zIndex,
  );
}

bool _listOfListsEquals(List<List<LatLng>> left, List<List<LatLng>> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!listEquals(left[index], right[index])) return false;
  }
  return true;
}

class GoogleMapController {
  GoogleMapController._(navigation.GoogleMapViewController delegate)
    : _delegate = delegate;

  navigation.GoogleMapViewController? _delegate;

  Future<void> animateCamera(CameraUpdate update) async {
    final delegate = _delegate;
    if (delegate == null) return;
    await delegate.animateCamera(update.toNavigation());
  }

  void dispose() {
    _delegate = null;
  }
}

/// Declarative compatibility widget backed by Google Navigation's map view.
///
/// The Navigation Flutter package manages overlays imperatively. This adapter
/// keeps the rest of VolTrike declarative and synchronizes stable marker and
/// polyline IDs with native overlay handles.
class GoogleMap extends StatefulWidget {
  const GoogleMap({
    super.key,
    required this.initialCameraPosition,
    this.onMapCreated,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = false,
    this.trafficEnabled = false,
    this.compassEnabled = true,
    this.buildingsEnabled = true,
    this.mapToolbarEnabled = true,
    this.zoomControlsEnabled = true,
    this.padding = EdgeInsets.zero,
    this.markers = const <Marker>{},
    this.polygons = const <Polygon>{},
    this.polylines = const <Polyline>{},
  });

  final CameraPosition initialCameraPosition;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool trafficEnabled;
  final bool compassEnabled;
  final bool buildingsEnabled;
  final bool mapToolbarEnabled;
  final bool zoomControlsEnabled;
  final EdgeInsets padding;
  final Set<Marker> markers;
  final Set<Polygon> polygons;
  final Set<Polyline> polylines;

  @override
  State<GoogleMap> createState() => _GoogleMapState();
}

class _GoogleMapState extends State<GoogleMap> {
  navigation.GoogleMapViewController? _controller;
  final Map<String, Marker> _markerSpecs = <String, Marker>{};
  final Map<String, navigation.Marker> _nativeMarkers =
      <String, navigation.Marker>{};
  final Map<String, Polygon> _polygonSpecs = <String, Polygon>{};
  final Map<String, navigation.Polygon> _nativePolygons =
      <String, navigation.Polygon>{};
  final Map<String, Polyline> _polylineSpecs = <String, Polyline>{};
  final Map<String, navigation.Polyline> _nativePolylines =
      <String, navigation.Polyline>{};

  bool _syncing = false;
  bool _syncPending = false;
  Brightness? _brightness;

  navigation.MapColorScheme get _mapColorScheme =>
      _brightness == Brightness.dark
      ? navigation.MapColorScheme.dark
      : navigation.MapColorScheme.light;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    if (_controller != null) {
      unawaited(_configureView());
    }
  }

  @override
  void didUpdateWidget(covariant GoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null) {
      unawaited(_configureView());
      _scheduleOverlaySync();
    }
  }

  Future<void> _onViewCreated(
    navigation.GoogleMapViewController controller,
  ) async {
    _controller = controller;
    await _configureView();
    _scheduleOverlaySync();
    widget.onMapCreated?.call(GoogleMapController._(controller));
  }

  Future<void> _configureView() async {
    final controller = _controller;
    if (controller == null) return;

    await _safe(
      () => controller.setMyLocationEnabled(widget.myLocationEnabled),
    );
    await _safe(
      () => controller.settings.setMyLocationButtonEnabled(
        widget.myLocationButtonEnabled,
      ),
    );
    await _safe(
      () => controller.settings.setTrafficEnabled(widget.trafficEnabled),
    );
    await _safe(() => controller.setBuildingsEnabled(widget.buildingsEnabled));
    await _safe(
      () => controller.settings.setCompassEnabled(widget.compassEnabled),
    );
    await _safe(
      () => controller.settings.setMapToolbarEnabled(widget.mapToolbarEnabled),
    );
    await _safe(
      () => controller.settings.setZoomControlsEnabled(
        widget.zoomControlsEnabled,
      ),
    );
    await _safe(() => controller.setPadding(widget.padding));
    await _safe(() => controller.setMapColorScheme(_mapColorScheme));
  }

  Future<void> _safe(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      debugPrint('Map configuration skipped: $error');
    }
  }

  void _scheduleOverlaySync() {
    _syncPending = true;
    if (_syncing) return;
    unawaited(_runOverlaySync());
  }

  Future<void> _runOverlaySync() async {
    _syncing = true;
    try {
      while (_syncPending && mounted && _controller != null) {
        _syncPending = false;
        await _syncPolygons();
        await _syncPolylines();
        await _syncMarkers();
      }
    } catch (error, stackTrace) {
      debugPrint('Map overlay synchronization failed: $error\n$stackTrace');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncMarkers() async {
    final controller = _controller;
    if (controller == null) return;
    final desired = <String, Marker>{
      for (final marker in widget.markers) marker.markerId.value: marker,
    };

    final removedIds = _nativeMarkers.keys
        .where((id) => !desired.containsKey(id))
        .toList();
    if (removedIds.isNotEmpty) {
      await controller.removeMarkers(
        removedIds.map((id) => _nativeMarkers[id]!).toList(),
      );
      for (final id in removedIds) {
        _nativeMarkers.remove(id);
        _markerSpecs.remove(id);
      }
    }

    final addedSpecs = desired.entries
        .where((entry) => !_nativeMarkers.containsKey(entry.key))
        .toList();
    if (addedSpecs.isNotEmpty) {
      final options = <navigation.MarkerOptions>[];
      for (final entry in addedSpecs) {
        options.add(await _markerOptions(entry.value));
      }
      final handles = await controller.addMarkers(options);
      for (var index = 0; index < addedSpecs.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = addedSpecs[index];
        _nativeMarkers[entry.key] = handle;
        _markerSpecs[entry.key] = entry.value;
      }
    }

    final changedEntries = desired.entries
        .where(
          (entry) =>
              _nativeMarkers.containsKey(entry.key) &&
              _markerSpecs[entry.key] != entry.value,
        )
        .toList();
    if (changedEntries.isNotEmpty) {
      final updates = <navigation.Marker>[];
      for (final entry in changedEntries) {
        updates.add(
          _nativeMarkers[entry.key]!.copyWith(
            options: await _markerOptions(entry.value),
          ),
        );
      }
      final handles = await controller.updateMarkers(updates);
      for (var index = 0; index < changedEntries.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = changedEntries[index];
        _nativeMarkers[entry.key] = handle;
        _markerSpecs[entry.key] = entry.value;
      }
    }
  }

  Future<navigation.MarkerOptions> _markerOptions(Marker marker) async {
    return navigation.MarkerOptions(
      position: marker.position.toNavigation(),
      infoWindow: navigation.InfoWindow(
        title: marker.infoWindow.title,
        snippet: marker.infoWindow.snippet,
      ),
      icon: await _MapImageRegistry.resolve(marker.icon),
      anchor: navigation.MarkerAnchor(u: marker.anchor.dx, v: marker.anchor.dy),
      rotation: marker.rotation,
      flat: marker.flat,
    );
  }

  Future<void> _syncPolygons() async {
    final controller = _controller;
    if (controller == null) return;
    final desired = <String, Polygon>{
      for (final polygon in widget.polygons) polygon.polygonId.value: polygon,
    };

    final removedIds = _nativePolygons.keys
        .where((id) => !desired.containsKey(id))
        .toList();
    if (removedIds.isNotEmpty) {
      await controller.removePolygons(
        removedIds.map((id) => _nativePolygons[id]!).toList(),
      );
      for (final id in removedIds) {
        _nativePolygons.remove(id);
        _polygonSpecs.remove(id);
      }
    }

    final addedSpecs = desired.entries
        .where((entry) => !_nativePolygons.containsKey(entry.key))
        .toList();
    if (addedSpecs.isNotEmpty) {
      final handles = await controller.addPolygons(
        addedSpecs.map((entry) => _polygonOptions(entry.value)).toList(),
      );
      for (var index = 0; index < addedSpecs.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = addedSpecs[index];
        _nativePolygons[entry.key] = handle;
        _polygonSpecs[entry.key] = entry.value;
      }
    }

    final changedEntries = desired.entries
        .where(
          (entry) =>
              _nativePolygons.containsKey(entry.key) &&
              _polygonSpecs[entry.key] != entry.value,
        )
        .toList();
    if (changedEntries.isNotEmpty) {
      final handles = await controller.updatePolygons(
        changedEntries
            .map(
              (entry) => _nativePolygons[entry.key]!.copyWith(
                options: _polygonOptions(entry.value),
              ),
            )
            .toList(),
      );
      for (var index = 0; index < changedEntries.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = changedEntries[index];
        _nativePolygons[entry.key] = handle;
        _polygonSpecs[entry.key] = entry.value;
      }
    }
  }

  navigation.PolygonOptions _polygonOptions(Polygon polygon) {
    return navigation.PolygonOptions(
      points: polygon.points.map((point) => point.toNavigation()).toList(),
      holes: polygon.holes
          .map((hole) => hole.map((point) => point.toNavigation()).toList())
          .toList(),
      fillColor: polygon.fillColor,
      strokeColor: polygon.strokeColor,
      strokeWidth: polygon.strokeWidth.toDouble(),
      geodesic: polygon.geodesic,
      visible: polygon.visible,
      zIndex: polygon.zIndex,
    );
  }

  Future<void> _syncPolylines() async {
    final controller = _controller;
    if (controller == null) return;
    final desired = <String, Polyline>{
      for (final polyline in widget.polylines)
        polyline.polylineId.value: polyline,
    };

    final removedIds = _nativePolylines.keys
        .where((id) => !desired.containsKey(id))
        .toList();
    if (removedIds.isNotEmpty) {
      await controller.removePolylines(
        removedIds.map((id) => _nativePolylines[id]!).toList(),
      );
      for (final id in removedIds) {
        _nativePolylines.remove(id);
        _polylineSpecs.remove(id);
      }
    }

    final addedSpecs = desired.entries
        .where((entry) => !_nativePolylines.containsKey(entry.key))
        .toList();
    if (addedSpecs.isNotEmpty) {
      final handles = await controller.addPolylines(
        addedSpecs.map((entry) => _polylineOptions(entry.value)).toList(),
      );
      for (var index = 0; index < addedSpecs.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = addedSpecs[index];
        _nativePolylines[entry.key] = handle;
        _polylineSpecs[entry.key] = entry.value;
      }
    }

    final changedEntries = desired.entries
        .where(
          (entry) =>
              _nativePolylines.containsKey(entry.key) &&
              _polylineSpecs[entry.key] != entry.value,
        )
        .toList();
    if (changedEntries.isNotEmpty) {
      final handles = await controller.updatePolylines(
        changedEntries
            .map(
              (entry) => _nativePolylines[entry.key]!.copyWith(
                options: _polylineOptions(entry.value),
              ),
            )
            .toList(),
      );
      for (var index = 0; index < changedEntries.length; index++) {
        final handle = handles[index];
        if (handle == null) continue;
        final entry = changedEntries[index];
        _nativePolylines[entry.key] = handle;
        _polylineSpecs[entry.key] = entry.value;
      }
    }
  }

  navigation.PolylineOptions _polylineOptions(Polyline polyline) {
    return navigation.PolylineOptions(
      points: polyline.points.map((point) => point.toNavigation()).toList(),
      strokeWidth: polyline.width.toDouble(),
      strokeColor: polyline.color,
      geodesic: polyline.geodesic,
      visible: polyline.visible,
    );
  }

  @override
  Widget build(BuildContext context) {
    return navigation.GoogleMapsMapView(
      initialCameraPosition: widget.initialCameraPosition.toNavigation(),
      initialCompassEnabled: widget.compassEnabled,
      initialMapToolbarEnabled: widget.mapToolbarEnabled,
      initialZoomControlsEnabled: widget.zoomControlsEnabled,
      initialPadding: widget.padding,
      initialMapColorScheme: _mapColorScheme,
      onViewCreated: _onViewCreated,
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}

class _MapImageRegistry {
  _MapImageRegistry._();

  static final Map<String, Future<navigation.ImageDescriptor>> _images =
      <String, Future<navigation.ImageDescriptor>>{};

  static Future<navigation.ImageDescriptor> resolve(
    BitmapDescriptor descriptor,
  ) {
    if (descriptor._kind == _BitmapDescriptorKind.defaultMarker) {
      return SynchronousFuture(navigation.ImageDescriptor.defaultImage);
    }
    final key = descriptor.cacheKey!;
    return _images.putIfAbsent(key, () => _register(descriptor));
  }

  static Future<navigation.ImageDescriptor> _register(
    BitmapDescriptor descriptor,
  ) async {
    final Uint8List bytes;
    if (descriptor._kind == _BitmapDescriptorKind.bytes) {
      bytes = descriptor.byteData!;
    } else {
      bytes = await _createHueMarker(descriptor.hue!);
    }
    return navigation.registerBitmapImage(
      bitmap: ByteData.sublistView(bytes),
      imagePixelRatio: 1,
    );
  }

  static Future<Uint8List> _createHueMarker(double hue) async {
    const size = 42.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final color = HSVColor.fromAHSV(1, hue, 0.82, 0.86).toColor();
    final shadowPaint = ui.Paint()..color = const Color(0x33000000);
    final markerPaint = ui.Paint()..color = color;
    final whitePaint = ui.Paint()..color = Colors.white;

    canvas.drawCircle(const ui.Offset(21, 22), 18, shadowPaint);
    canvas.drawCircle(const ui.Offset(21, 19), 17, markerPaint);
    canvas.drawCircle(const ui.Offset(21, 19), 7, whitePaint);

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Could not create a map marker image.');
    }
    return data.buffer.asUint8List();
  }
}
