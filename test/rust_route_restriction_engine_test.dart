import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/native/route_restriction_engine.dart';
import 'package:voltrike_v2/core/native/rust_geometry_bridge.dart';
import 'package:voltrike_v2/core/native/rust_migration_mode.dart';
import 'package:voltrike_v2/core/services/route_restriction_matcher.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';

void main() {
  const crossingRoute = <LatLng>[LatLng(10.65, 122.95), LatLng(10.69, 122.95)];
  final restrictions = <RouteRestriction>[
    _restriction(id: 'legacy-corridor', west: 122.94, geometryType: 'corridor'),
    _restriction(id: 'first', west: 122.94),
    _restriction(id: 'second', west: 122.98),
  ];

  group('Rust migration mode', () {
    test('parses only explicit shadow and on values', () {
      expect(RustMigrationMode.parse('shadow'), RustMigrationMode.shadow);
      expect(RustMigrationMode.parse(' ON '), RustMigrationMode.on);
      expect(RustMigrationMode.parse('unexpected'), RustMigrationMode.off);
    });
  });

  group('RouteRestrictionEngine rollout behavior', () {
    test('off returns Dart result without crossing the bridge', () async {
      final bridge = _FakeRustGeometryBridge(response: const [1]);
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.off,
        rustBridge: bridge,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 1);
      expect(bridge.callCount, 0);
    });

    test('shadow compares native output but returns Dart result', () async {
      final messages = <String>[];
      final bridge = _FakeRustGeometryBridge(response: const [1]);
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.shadow,
        rustBridge: bridge,
        reporter: messages.add,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 1);
      expect(bridge.callCount, 1);
      expect(messages.single, contains('matched=false'));
    });

    test('on maps native indices back to original restriction order', () async {
      final bridge = _FakeRustGeometryBridge(response: const [1]);
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 2);
      expect(bridge.lastRequest!.restrictionAreaCounts, [1, 1]);
      expect(bridge.lastRequest!.areaPointCounts, [4, 4]);
      expect(bridge.lastRequest!.routeLatLng, [10.65, 122.95, 10.69, 122.95]);
    });

    test('bridge failures always fall back to Dart', () async {
      final messages = <String>[];
      final bridge = _FakeRustGeometryBridge(error: StateError('load failed'));
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
        reporter: messages.add,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 1);
      expect(messages.single, contains('fallback'));
    });

    test('fallback rejects invalid coordinates before Dart matching', () async {
      final bridge = _FakeRustGeometryBridge(error: StateError('load failed'));
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
      );

      await expectLater(
        engine.firstRouteConflictIndex(
          route: const [LatLng(double.nan, 122.95), LatLng(10.69, 122.95)],
          restrictions: restrictions,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('invalid coordinate'),
          ),
        ),
      );
      expect(bridge.callCount, 1);
    });

    test('unsupported platforms stay on Dart in on mode', () async {
      final bridge = _FakeRustGeometryBridge(
        isSupported: false,
        response: const [1],
      );
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 1);
      expect(bridge.callCount, 0);
    });

    test('out-of-range native indices fall back safely', () async {
      final messages = <String>[];
      final bridge = _FakeRustGeometryBridge(response: const [99]);
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
        reporter: messages.add,
      );

      final result = await engine.firstRouteConflictIndex(
        route: crossingRoute,
        restrictions: restrictions,
      );

      expect(result, 1);
      expect(messages.single, contains('out-of-range'));
    });
  });

  group('RouteRestrictionEngine cached geometry v2', () {
    const encodedCrossingRoute = 'oa_`AotlmV_yF?';

    test(
      'off decodes encoded routes in Dart without installing a cache',
      () async {
        final bridge = _FakeRustGeometryBridge(
          encodedResponse: const RustCachedRouteConflictResponse(
            cacheGeneration: 7,
            conflictingRestrictionIndices: [1],
          ),
        );
        final engine = RouteRestrictionEngine(
          mode: RustMigrationMode.off,
          rustBridge: bridge,
        );

        final result = await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: encodedCrossingRoute,
          restrictions: restrictions,
        );

        expect(result, 1);
        expect(bridge.cacheReplaceCallCount, 0);
        expect(bridge.encodedCallCount, 0);
      },
    );

    test('off rejects malformed encoded routes without using Rust', () async {
      final bridge = _FakeRustGeometryBridge();
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.off,
        rustBridge: bridge,
      );

      await expectLater(
        engine.firstEncodedRouteConflictIndex(
          encodedPolyline: '_',
          restrictions: restrictions,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(bridge.cacheReplaceCallCount, 0);
      expect(bridge.encodedCallCount, 0);
    });

    test(
      'on installs once, reuses cache, and restores original order',
      () async {
        final bridge = _FakeRustGeometryBridge(
          encodedResponse: const RustCachedRouteConflictResponse(
            cacheGeneration: 7,
            conflictingRestrictionIndices: [1],
          ),
        );
        final engine = RouteRestrictionEngine(
          mode: RustMigrationMode.on,
          rustBridge: bridge,
        );

        final first = await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: encodedCrossingRoute,
          restrictions: restrictions,
        );
        final second = await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: encodedCrossingRoute,
          restrictions: restrictions,
        );

        expect(first, 2);
        expect(second, 2);
        expect(bridge.cacheReplaceCallCount, 1);
        expect(bridge.encodedCallCount, 2);
        expect(bridge.lastCacheRequest!.restrictionAreaCounts, [1, 1]);
        expect(bridge.lastCacheRequest!.areaPointCounts, [4, 4]);
        expect(bridge.lastEncodedRequest!.expectedCacheGeneration, 7);
      },
    );

    test(
      'cache generation mismatches fall back and force a reinstall',
      () async {
        final messages = <String>[];
        final bridge = _FakeRustGeometryBridge(
          encodedResponse: const RustCachedRouteConflictResponse(
            cacheGeneration: 8,
            conflictingRestrictionIndices: [1],
          ),
        );
        final engine = RouteRestrictionEngine(
          mode: RustMigrationMode.on,
          rustBridge: bridge,
          reporter: messages.add,
        );

        final first = await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: encodedCrossingRoute,
          restrictions: restrictions,
        );
        final second = await engine.firstEncodedRouteConflictIndex(
          encodedPolyline: encodedCrossingRoute,
          restrictions: restrictions,
        );

        expect(first, 1);
        expect(second, 1);
        expect(bridge.cacheReplaceCallCount, 2);
        expect(messages, everyElement(contains('fallback')));
      },
    );

    test(
      'point proximity maps cache indices and preferred restriction',
      () async {
        final bridge = _FakeRustGeometryBridge(
          pointResponse: const RustPointProximityResponse(
            cacheGeneration: 7,
            insideRestrictionIndex: 0,
            nearestRestrictionIndex: 0,
            nearestDistanceMeters: 0,
            preferredDistanceMeters: 400,
          ),
        );
        final engine = RouteRestrictionEngine(
          mode: RustMigrationMode.on,
          proximityMode: RustMigrationMode.on,
          rustBridge: bridge,
        );

        final result = await engine.pointProximity(
          point: const LatLng(10.67, 122.95),
          restrictions: restrictions,
          preferredRestrictionId: 'second',
        );

        expect(result.insideRestrictionIndex, 1);
        expect(result.nearestRestrictionIndex, 1);
        expect(result.nearestDistanceMeters, 0);
        expect(result.preferredDistanceMeters, 400);
        expect(bridge.lastPointRequest!.preferredRestrictionIndex, 1);
        expect(bridge.lastPointRequest!.expectedCacheGeneration, 7);
      },
    );

    test('point proximity bridge failures preserve Dart behavior', () async {
      final messages = <String>[];
      final bridge = _FakeRustGeometryBridge(
        proximityError: StateError('query failed'),
      );
      final engine = RouteRestrictionEngine(
        mode: RustMigrationMode.on,
        proximityMode: RustMigrationMode.on,
        rustBridge: bridge,
        reporter: messages.add,
      );

      final result = await engine.pointProximity(
        point: const LatLng(10.67, 122.95),
        restrictions: restrictions,
        preferredRestrictionId: 'first',
      );

      expect(result.insideRestrictionIndex, 1);
      expect(result.nearestRestrictionIndex, 1);
      expect(result.nearestDistanceMeters, 0);
      expect(result.preferredDistanceMeters, 0);
      expect(messages.single, contains('fallback'));
    });

    test(
      'geometry rollout keeps measured-small proximity queries on Dart',
      () async {
        final bridge = _FakeRustGeometryBridge();
        final engine = RouteRestrictionEngine(
          mode: RustMigrationMode.on,
          rustBridge: bridge,
        );

        final result = await engine.pointProximity(
          point: const LatLng(10.67, 122.95),
          restrictions: restrictions,
          preferredRestrictionId: 'first',
        );

        expect(result.insideRestrictionIndex, 1);
        expect(result.nearestRestrictionIndex, 1);
        expect(result.nearestDistanceMeters, 0);
        expect(result.preferredDistanceMeters, 0);
        expect(bridge.proximityCallCount, 0);
      },
    );
  });

  test('shared JSON fixtures match the Dart reference implementation', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/route_restriction_parity.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(fixture['coordinate_order'], 'latitude_longitude');

    final cases = fixture['cases']! as List<dynamic>;
    for (final rawCase in cases.cast<Map<String, dynamic>>()) {
      final route = _points(rawCase['route']);
      final fixtureRestrictions = (rawCase['restrictions']! as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (rawRestriction) => RouteRestriction(
              id: rawCase['name']! as String,
              name: rawCase['name']! as String,
              type: 'no_service_area',
              polygon: _points(
                (rawRestriction['areas']! as List<dynamic>).first,
              ),
              areas: (rawRestriction['areas']! as List<dynamic>)
                  .map(_points)
                  .toList(growable: false),
              geometryType: 'polygon',
              isActive: true,
            ),
          )
          .toList(growable: false);

      final actual = <int>[];
      for (var index = 0; index < fixtureRestrictions.length; index++) {
        if (RouteRestrictionMatcher.routeConflicts(
          route,
          fixtureRestrictions[index],
        )) {
          actual.add(index);
          break;
        }
      }

      expect(
        actual,
        (rawCase['expected_conflict_indices']! as List<dynamic>).cast<int>(),
        reason: rawCase['name']! as String,
      );
    }
  });
}

class _FakeRustGeometryBridge implements RustGeometryBridge {
  _FakeRustGeometryBridge({
    this.isSupported = true,
    this.response = const <int>[],
    this.error,
    this.encodedResponse = const RustCachedRouteConflictResponse(
      cacheGeneration: 7,
      conflictingRestrictionIndices: <int>[],
    ),
    this.pointResponse = const RustPointProximityResponse(cacheGeneration: 7),
    this.proximityError,
  });

  @override
  final bool isSupported;
  final List<int> response;
  final Object? error;
  final RustRestrictionCacheResponse cacheResponse =
      const RustRestrictionCacheResponse(
        cacheGeneration: 7,
        restrictionCount: 2,
      );
  final RustCachedRouteConflictResponse encodedResponse;
  final RustPointProximityResponse pointResponse;
  final Object? proximityError;
  int callCount = 0;
  int cacheReplaceCallCount = 0;
  int encodedCallCount = 0;
  int proximityCallCount = 0;
  RustRouteConflictRequest? lastRequest;
  RustRestrictionCacheRequest? lastCacheRequest;
  RustEncodedRouteConflictRequest? lastEncodedRequest;
  RustPointProximityRequest? lastPointRequest;

  @override
  Future<RustRouteConflictResponse> analyzeRouteConflicts(
    RustRouteConflictRequest request,
  ) async {
    callCount++;
    lastRequest = request;
    final failure = error;
    if (failure != null) throw failure;
    return RustRouteConflictResponse(conflictingRestrictionIndices: response);
  }

  @override
  Future<RustRestrictionCacheResponse> replaceRestrictionCache(
    RustRestrictionCacheRequest request,
  ) async {
    cacheReplaceCallCount++;
    lastCacheRequest = request;
    return cacheResponse;
  }

  @override
  Future<RustCachedRouteConflictResponse> analyzeCachedEncodedRouteConflicts(
    RustEncodedRouteConflictRequest request,
  ) async {
    encodedCallCount++;
    lastEncodedRequest = request;
    return encodedResponse;
  }

  @override
  Future<RustPointProximityResponse> queryCachedPointProximity(
    RustPointProximityRequest request,
  ) async {
    proximityCallCount++;
    lastPointRequest = request;
    final failure = proximityError;
    if (failure != null) throw failure;
    return pointResponse;
  }
}

RouteRestriction _restriction({
  required String id,
  required double west,
  String geometryType = 'polygon',
}) {
  final polygon = <LatLng>[
    LatLng(10.66, west),
    LatLng(10.66, west + 0.02),
    LatLng(10.68, west + 0.02),
    LatLng(10.68, west),
  ];
  return RouteRestriction(
    id: id,
    name: id,
    type: geometryType == 'corridor' ? 'prohibited_highway' : 'no_service_area',
    polygon: polygon,
    areas: [polygon],
    geometryType: geometryType,
    isActive: true,
  );
}

List<LatLng> _points(Object? rawPoints) {
  return (rawPoints! as List<dynamic>)
      .cast<List<dynamic>>()
      .map(
        (point) =>
            LatLng((point[0] as num).toDouble(), (point[1] as num).toDouble()),
      )
      .toList(growable: false);
}
