import 'package:cloud_firestore/cloud_firestore.dart';

import '../maps/voltrike_map.dart';

typedef TodaCoverageZoneLoader = Future<List<TodaCoverageZone>> Function();

enum TodaTripCoverageStatus {
  sameZone,
  crossBoundary,
  pickupOutside,
  unconfigured,
}

class TodaCoverageDecision {
  const TodaCoverageDecision({
    required this.status,
    this.pickupTodaIds = const <String>[],
    this.destinationTodaIds = const <String>[],
    this.serviceTodaId,
  });

  final TodaTripCoverageStatus status;
  final List<String> pickupTodaIds;
  final List<String> destinationTodaIds;
  final String? serviceTodaId;

  /// Coverage affects dispatch priority and fees, not whether pickup is legal.
  bool get pickupAllowed => true;

  bool get isOutsideToda =>
      status == TodaTripCoverageStatus.crossBoundary ||
      status == TodaTripCoverageStatus.pickupOutside;
}

class TodaCoverageZone {
  const TodaCoverageZone({required this.todaId, required this.areas});

  final String todaId;
  final List<List<LatLng>> areas;

  bool contains(LatLng point) {
    return areas.any((area) => _polygonContains(point, area));
  }

  /// Parses both the Firestore-safe schema and the legacy array schema.
  ///
  /// Firestore-safe:
  /// `areas: [{points: [{latitude: 10, longitude: 122}, ...]}]`
  ///
  /// Legacy:
  /// `areas: [[[122, 10], ...]]` or `polygon: [[122, 10], ...]`
  static TodaCoverageZone? fromMap({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    if (data['isActive'] == false) return null;

    final todaId = _readTodaId(data['todaId']) ?? documentId.trim();
    if (todaId.isEmpty) return null;

    var areas = _parseAreas(data['areas']);
    if (areas.isEmpty) {
      areas = _parseAreas(data['polygon']);
    }
    if (areas.isEmpty) return null;

    return TodaCoverageZone(
      todaId: todaId,
      areas: List<List<LatLng>>.unmodifiable(areas),
    );
  }

  static String? _readTodaId(dynamic value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<List<LatLng>> _parseAreas(dynamic rawAreas) {
    if (rawAreas == null) return const <List<LatLng>>[];

    final Iterable<dynamic> candidates;
    if (rawAreas is Map) {
      if (_pointsFromArea(rawAreas) != null) {
        candidates = <dynamic>[rawAreas];
      } else {
        candidates = rawAreas.values;
      }
    } else if (rawAreas is Iterable) {
      final values = rawAreas.toList(growable: false);
      if (values.isEmpty) return const <List<LatLng>>[];
      candidates = _looksLikePointCollection(values)
          ? <dynamic>[values]
          : values;
    } else {
      return const <List<LatLng>>[];
    }

    return candidates
        .map(_parseArea)
        .whereType<List<LatLng>>()
        .toList(growable: false);
  }

  static bool _looksLikePointCollection(List<dynamic> values) {
    return values.isNotEmpty && _parsePoint(values.first) != null;
  }

  static List<LatLng>? _parseArea(dynamic rawArea) {
    final rawPoints = _pointsFromArea(rawArea);
    if (rawPoints == null) return null;

    final values = rawPoints is Map
        ? rawPoints.values
        : rawPoints is Iterable
        ? rawPoints
        : null;
    if (values == null) return null;

    final points = values
        .map(_parsePoint)
        .whereType<LatLng>()
        .toList(growable: true);
    if (points.length > 1 && points.first == points.last) {
      points.removeLast();
    }
    if (points.toSet().length < 3) return null;
    return List<LatLng>.unmodifiable(points);
  }

  static dynamic _pointsFromArea(dynamic rawArea) {
    if (rawArea is Map) {
      return rawArea['points'] ?? rawArea['coordinates'] ?? rawArea['polygon'];
    }
    return rawArea;
  }

  static LatLng? _parsePoint(dynamic rawPoint) {
    if (rawPoint is LatLng) return rawPoint;
    if (rawPoint is GeoPoint) {
      return _validPoint(rawPoint.latitude, rawPoint.longitude);
    }
    if (rawPoint is Map) {
      final latitude = _asDouble(rawPoint['latitude'] ?? rawPoint['lat']);
      final longitude = _asDouble(
        rawPoint['longitude'] ?? rawPoint['lng'] ?? rawPoint['lon'],
      );
      if (latitude == null || longitude == null) return null;
      return _validPoint(latitude, longitude);
    }
    if (rawPoint is List && rawPoint.length >= 2) {
      // Coverage editors and legacy GeoJSON store longitude before latitude.
      final longitude = _asDouble(rawPoint[0]);
      final latitude = _asDouble(rawPoint[1]);
      if (latitude == null || longitude == null) return null;
      return _validPoint(latitude, longitude);
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  static LatLng? _validPoint(double latitude, double longitude) {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  static bool _polygonContains(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    var inside = false;
    for (
      var index = 0, previous = polygon.length - 1;
      index < polygon.length;
      previous = index++
    ) {
      final start = polygon[previous];
      final end = polygon[index];
      if (_pointOnSegment(point, start, end)) return true;

      final crossesLatitude =
          (end.latitude > point.latitude) != (start.latitude > point.latitude);
      if (!crossesLatitude) continue;

      final crossingLongitude =
          (start.longitude - end.longitude) *
              (point.latitude - end.latitude) /
              (start.latitude - end.latitude) +
          end.longitude;
      if (point.longitude < crossingLongitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _pointOnSegment(LatLng point, LatLng start, LatLng end) {
    const epsilon = 1e-10;
    final cross =
        (point.latitude - start.latitude) * (end.longitude - start.longitude) -
        (point.longitude - start.longitude) * (end.latitude - start.latitude);
    if (cross.abs() > epsilon) return false;

    return point.latitude >=
            (start.latitude < end.latitude ? start.latitude : end.latitude) -
                epsilon &&
        point.latitude <=
            (start.latitude > end.latitude ? start.latitude : end.latitude) +
                epsilon &&
        point.longitude >=
            (start.longitude < end.longitude
                    ? start.longitude
                    : end.longitude) -
                epsilon &&
        point.longitude <=
            (start.longitude > end.longitude
                    ? start.longitude
                    : end.longitude) +
                epsilon;
  }
}

class TodaCoverageService {
  TodaCoverageService({
    FirebaseFirestore? firestore,
    TodaCoverageZoneLoader? loader,
    this.cacheDuration = const Duration(minutes: 5),
  }) : _loader = loader,
       _firestore = loader == null
           ? (firestore ?? FirebaseFirestore.instance)
           : firestore;

  static final TodaCoverageService instance = TodaCoverageService();

  final FirebaseFirestore? _firestore;
  final TodaCoverageZoneLoader? _loader;
  final Duration cacheDuration;

  List<TodaCoverageZone>? _cachedZones;
  DateTime? _loadedAt;

  Future<TodaCoverageDecision> classifyTrip({
    required LatLng pickup,
    required LatLng destination,
    bool forceRefresh = false,
  }) async {
    final zones = await activeZones(forceRefresh: forceRefresh);
    return classify(pickup: pickup, destination: destination, zones: zones);
  }

  Future<List<TodaCoverageZone>> activeZones({
    bool forceRefresh = false,
  }) async {
    final loadedAt = _loadedAt;
    if (!forceRefresh &&
        _cachedZones != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < cacheDuration) {
      return _cachedZones!;
    }

    final zones = _loader != null
        ? await _loader()
        : await _loadFromFirestore();
    _cachedZones = List<TodaCoverageZone>.unmodifiable(zones);
    _loadedAt = DateTime.now();
    return _cachedZones!;
  }

  void invalidate() {
    _cachedZones = null;
    _loadedAt = null;
  }

  Future<List<TodaCoverageZone>> _loadFromFirestore() async {
    final snapshot = await _firestore!.collection('geofences').get();
    return snapshot.docs
        .map(
          (document) => TodaCoverageZone.fromMap(
            documentId: document.id,
            data: document.data(),
          ),
        )
        .whereType<TodaCoverageZone>()
        .toList(growable: false);
  }

  static TodaCoverageDecision classify({
    required LatLng pickup,
    required LatLng destination,
    required Iterable<TodaCoverageZone> zones,
  }) {
    final configuredZones = zones.toList(growable: false);
    if (configuredZones.isEmpty) {
      return const TodaCoverageDecision(
        status: TodaTripCoverageStatus.unconfigured,
      );
    }

    final pickupTodaIds =
        configuredZones
            .where((zone) => zone.contains(pickup))
            .map((zone) => zone.todaId)
            .toSet()
            .toList(growable: false)
          ..sort();
    final destinationTodaIds =
        configuredZones
            .where((zone) => zone.contains(destination))
            .map((zone) => zone.todaId)
            .toSet()
            .toList(growable: false)
          ..sort();

    if (pickupTodaIds.isEmpty) {
      return TodaCoverageDecision(
        status: TodaTripCoverageStatus.pickupOutside,
        destinationTodaIds: List<String>.unmodifiable(destinationTodaIds),
        serviceTodaId: destinationTodaIds.length == 1
            ? destinationTodaIds.first
            : null,
      );
    }

    final sharedTodaIds =
        pickupTodaIds.where(destinationTodaIds.contains).toList(growable: false)
          ..sort();
    if (sharedTodaIds.isNotEmpty) {
      return TodaCoverageDecision(
        status: TodaTripCoverageStatus.sameZone,
        pickupTodaIds: List<String>.unmodifiable(pickupTodaIds),
        destinationTodaIds: List<String>.unmodifiable(destinationTodaIds),
        serviceTodaId: sharedTodaIds.length == 1 ? sharedTodaIds.first : null,
      );
    }

    return TodaCoverageDecision(
      status: TodaTripCoverageStatus.crossBoundary,
      pickupTodaIds: List<String>.unmodifiable(pickupTodaIds),
      destinationTodaIds: List<String>.unmodifiable(destinationTodaIds),
      serviceTodaId: pickupTodaIds.length == 1 ? pickupTodaIds.first : null,
    );
  }
}
