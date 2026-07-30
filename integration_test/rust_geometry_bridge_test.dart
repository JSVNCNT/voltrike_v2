import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/native/route_restriction_engine.dart';
import 'package:voltrike_v2/core/native/rust_geometry_bridge.dart';
import 'package:voltrike_v2/core/native/rust_migration_mode.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android loads Rust and evaluates a geometry batch', (
    tester,
  ) async {
    final bridge = createRustGeometryBridge();
    expect(bridge.isSupported, isTrue);

    final result = await bridge.analyzeRouteConflicts(
      const RustRouteConflictRequest(
        routeLatLng: [10.65, 122.95, 10.69, 122.95],
        polygonLatLng: [
          10.66,
          122.94,
          10.66,
          122.96,
          10.68,
          122.96,
          10.68,
          122.94,
        ],
        areaPointCounts: [4],
        restrictionAreaCounts: [1],
      ),
    );

    expect(result.conflictingRestrictionIndices, [0]);
  });

  testWidgets('invalid native input returns a Dart error without crashing', (
    tester,
  ) async {
    final bridge = createRustGeometryBridge();

    await expectLater(
      bridge.analyzeRouteConflicts(
        const RustRouteConflictRequest(
          routeLatLng: [10.65],
          polygonLatLng: [],
          areaPointCounts: [],
          restrictionAreaCounts: [],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message.toString(),
          'message',
          contains('route coordinate buffer'),
        ),
      ),
    );
  });

  testWidgets('on mode filters and remaps restrictions through native Rust', (
    tester,
  ) async {
    const route = <LatLng>[LatLng(10.65, 122.99), LatLng(10.71, 122.99)];
    final restrictions = <RouteRestriction>[
      _restriction(
        id: 'legacy-corridor',
        west: 122.98,
        geometryType: 'corridor',
      ),
      _restriction(id: 'outside', west: 122.94),
      _restriction(id: 'multi-area', west: 123.04, additionalWest: 122.98),
    ];
    final messages = <String>[];
    final engine = RouteRestrictionEngine(
      mode: RustMigrationMode.on,
      rustBridge: createRustGeometryBridge(),
      reporter: messages.add,
    );

    final result = await engine.firstRouteConflictIndex(
      route: route,
      restrictions: restrictions,
    );

    expect(result, 2);
    expect(
      messages,
      isEmpty,
      reason: 'The real native path must not fall back.',
    );
  });

  testWidgets(
    'v2 cache, fused polyline, and proximity cross the Android bridge',
    (tester) async {
      final bridge = createRustGeometryBridge();
      const polygon = <LatLng>[
        LatLng(10.66, 122.94),
        LatLng(10.66, 122.96),
        LatLng(10.68, 122.96),
        LatLng(10.68, 122.94),
      ];
      final cache = await bridge.replaceRestrictionCache(
        const RustRestrictionCacheRequest(
          polygonLatLng: [
            10.66,
            122.94,
            10.66,
            122.96,
            10.68,
            122.96,
            10.68,
            122.94,
          ],
          areaPointCounts: [4],
          restrictionAreaCounts: [1],
        ),
      );

      expect(cache.cacheGeneration, greaterThan(0));
      expect(cache.restrictionCount, 1);

      final conflict = await bridge.analyzeCachedEncodedRouteConflicts(
        RustEncodedRouteConflictRequest(
          encodedPolyline: _encodePolyline(const [
            LatLng(10.65, 122.95),
            LatLng(10.69, 122.95),
          ]),
          expectedCacheGeneration: cache.cacheGeneration,
        ),
      );
      expect(conflict.cacheGeneration, cache.cacheGeneration);
      expect(conflict.conflictingRestrictionIndices, [0]);

      final proximity = await bridge.queryCachedPointProximity(
        RustPointProximityRequest(
          latitude: 10.67,
          longitude: 122.95,
          expectedCacheGeneration: cache.cacheGeneration,
          preferredRestrictionIndex: 0,
        ),
      );
      expect(proximity.cacheGeneration, cache.cacheGeneration);
      expect(proximity.insideRestrictionIndex, 0);
      expect(proximity.nearestRestrictionIndex, 0);
      expect(proximity.nearestDistanceMeters, 0);
      expect(proximity.preferredDistanceMeters, 0);

      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        proximityMode: RustMigrationMode.on,
        rustBridge: bridge,
      );
      final restriction = RouteRestriction(
        id: 'cached-area',
        name: 'Cached area',
        type: 'no_service_area',
        polygon: polygon,
        areas: const [polygon],
        isActive: true,
      );
      expect(
        await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: _encodePolyline(const [
            LatLng(10.65, 122.95),
            LatLng(10.69, 122.95),
          ]),
          restrictions: [restriction],
        ),
        0,
      );
      final engineProximity = await engine.pointProximity(
        point: const LatLng(10.67, 122.95),
        restrictions: [restriction],
        preferredRestrictionId: restriction.id,
      );
      expect(engineProximity.insideRestrictionIndex, 0);
      expect(engineProximity.nearestRestrictionIndex, 0);
      expect(engineProximity.preferredDistanceMeters, 0);
    },
  );
}

String _encodePolyline(List<LatLng> points) {
  final encoded = StringBuffer();
  var previousLatitude = 0;
  var previousLongitude = 0;

  void writeDelta(int delta) {
    var value = delta < 0 ? ~(delta << 1) : delta << 1;
    while (value >= 0x20) {
      encoded.writeCharCode((0x20 | (value & 0x1f)) + 63);
      value >>= 5;
    }
    encoded.writeCharCode(value + 63);
  }

  for (final point in points) {
    final latitude = (point.latitude * 100000).round();
    final longitude = (point.longitude * 100000).round();
    writeDelta(latitude - previousLatitude);
    writeDelta(longitude - previousLongitude);
    previousLatitude = latitude;
    previousLongitude = longitude;
  }
  return encoded.toString();
}

RouteRestriction _restriction({
  required String id,
  required double west,
  String geometryType = 'polygon',
  double? additionalWest,
}) {
  List<LatLng> area(double areaWest) => <LatLng>[
    LatLng(10.66, areaWest),
    LatLng(10.66, areaWest + 0.02),
    LatLng(10.70, areaWest + 0.02),
    LatLng(10.70, areaWest),
  ];

  final firstArea = area(west);
  final areas = <List<LatLng>>[
    firstArea,
    if (additionalWest != null) area(additionalWest),
  ];
  return RouteRestriction(
    id: id,
    name: id,
    type: geometryType == 'corridor' ? 'prohibited_highway' : 'no_service_area',
    polygon: firstArea,
    areas: areas,
    geometryType: geometryType,
    isActive: true,
  );
}
