import 'dart:convert';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/native/route_restriction_engine.dart';
import 'package:voltrike_v2/core/native/rust_geometry_bridge.dart';
import 'package:voltrike_v2/core/native/rust_migration_mode.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('benchmarks end-to-end Dart and Rust geometry paths', (
    tester,
  ) async {
    final bridge = createRustGeometryBridge();
    expect(bridge.isSupported, isTrue);
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final deviceReport = <String, Object>{
      'model': androidInfo.model,
      'androidRelease': androidInfo.version.release,
      'sdkInt': androidInfo.version.sdkInt,
      'supportedAbis': androidInfo.supportedAbis,
    };
    debugPrint('RUST_GEOMETRY_DEVICE ${jsonEncode(deviceReport)}');

    const scenarios = <_BenchmarkScenario>[
      _BenchmarkScenario(
        name: 'typical',
        routePointCount: 96,
        restrictionCount: 24,
        warmupCount: 6,
        sampleCount: 30,
        measureColdStart: true,
      ),
      _BenchmarkScenario(
        name: 'early-conflict',
        routePointCount: 96,
        restrictionCount: 24,
        warmupCount: 6,
        sampleCount: 30,
        firstRestrictionConflicts: true,
      ),
      _BenchmarkScenario(
        name: 'stress',
        routePointCount: 256,
        restrictionCount: 128,
        warmupCount: 6,
        sampleCount: 30,
      ),
    ];

    final reports = <Map<String, Object>>[];
    for (final scenario in scenarios) {
      final report = await _benchmarkScenario(
        scenario: scenario,
        bridge: bridge,
      );
      reports.add(report);
      debugPrint('RUST_GEOMETRY_BENCHMARK ${jsonEncode(report)}');
    }
    final cachedV2 = await _benchmarkCachedV2(bridge);
    debugPrint('RUST_GEOMETRY_V2_BENCHMARK ${jsonEncode(cachedV2)}');

    binding.reportData = <String, Object>{
      'device': deviceReport,
      'benchmarks': reports,
      'cachedV2': cachedV2,
    };
  });
}

Future<Map<String, Object>> _benchmarkCachedV2(
  RustGeometryBridge bridge,
) async {
  const sampleCount = 30;
  const warmupCount = 6;
  final route = List<LatLng>.generate(
    256,
    (index) =>
        LatLng(10.60 + index * 0.0001, 122.95 + math.sin(index / 12) * 0.001),
    growable: false,
  );
  final encodedRoute = _encodePolyline(route);
  final restrictions = List<RouteRestriction>.generate(
    128,
    _restrictionOutsideRoute,
    growable: false,
  );
  final dartEngine = RouteRestrictionEngine(
    mode: RustMigrationMode.off,
    rustBridge: bridge,
    reporter: (_) {},
  );
  final rustEngine = RouteRestrictionEngine(
    mode: RustMigrationMode.on,
    proximityMode: RustMigrationMode.on,
    rustBridge: bridge,
    reporter: (_) {},
  );

  Future<void> runEncoded(RouteRestrictionEngine engine) async {
    expect(
      await engine.firstEncodedRouteConflictIndex(
        encodedPolyline: encodedRoute,
        restrictions: restrictions,
      ),
      isNull,
    );
  }

  Future<void> runProximity(RouteRestrictionEngine engine) async {
    final result = await engine.pointProximity(
      point: const LatLng(10.625, 122.95),
      restrictions: restrictions,
      preferredRestrictionId: restrictions.last.id,
    );
    expect(result.insideRestrictionIndex, isNull);
    expect(result.nearestRestrictionIndex, isNotNull);
    expect(result.nearestDistanceMeters, greaterThan(0));
    expect(result.preferredDistanceMeters, greaterThan(0));
  }

  final dartColdEncodedUs = await _measureOperation(
    () => runEncoded(dartEngine),
  );
  final rustColdEncodedUs = await _measureOperation(
    () => runEncoded(rustEngine),
  );
  for (var index = 0; index < warmupCount; index++) {
    await runEncoded(dartEngine);
    await runEncoded(rustEngine);
    await runProximity(dartEngine);
    await runProximity(rustEngine);
  }

  final dartEncodedUs = <int>[];
  final rustEncodedUs = <int>[];
  final dartProximityUs = <int>[];
  final rustProximityUs = <int>[];
  for (var index = 0; index < sampleCount; index++) {
    if (index.isEven) {
      dartEncodedUs.add(await _measureOperation(() => runEncoded(dartEngine)));
      rustEncodedUs.add(await _measureOperation(() => runEncoded(rustEngine)));
      dartProximityUs.add(
        await _measureOperation(() => runProximity(dartEngine)),
      );
      rustProximityUs.add(
        await _measureOperation(() => runProximity(rustEngine)),
      );
    } else {
      rustEncodedUs.add(await _measureOperation(() => runEncoded(rustEngine)));
      dartEncodedUs.add(await _measureOperation(() => runEncoded(dartEngine)));
      rustProximityUs.add(
        await _measureOperation(() => runProximity(rustEngine)),
      );
      dartProximityUs.add(
        await _measureOperation(() => runProximity(dartEngine)),
      );
    }
  }

  final dartEncodedMedian = _percentile(dartEncodedUs, 0.5);
  final rustEncodedMedian = _percentile(rustEncodedUs, 0.5);
  final dartProximityMedian = _percentile(dartProximityUs, 0.5);
  final rustProximityMedian = _percentile(rustProximityUs, 0.5);
  return <String, Object>{
    'buildMode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'routePoints': route.length,
    'encodedBytes': encodedRoute.length,
    'restrictions': restrictions.length,
    'samples': sampleCount,
    'dartColdEncodedUs': dartColdEncodedUs,
    'rustColdEncodedAndCacheInstallUs': rustColdEncodedUs,
    'dartEncodedMedianUs': dartEncodedMedian,
    'dartEncodedP95Us': _percentile(dartEncodedUs, 0.95),
    'rustCachedEncodedMedianUs': rustEncodedMedian,
    'rustCachedEncodedP95Us': _percentile(rustEncodedUs, 0.95),
    'encodedDartToRustMedianRatio': dartEncodedMedian / rustEncodedMedian,
    'dartProximityMedianUs': dartProximityMedian,
    'dartProximityP95Us': _percentile(dartProximityUs, 0.95),
    'rustCachedProximityMedianUs': rustProximityMedian,
    'rustCachedProximityP95Us': _percentile(rustProximityUs, 0.95),
    'proximityDartToRustMedianRatio': dartProximityMedian / rustProximityMedian,
  };
}

Future<Map<String, Object>> _benchmarkScenario({
  required _BenchmarkScenario scenario,
  required RustGeometryBridge bridge,
}) async {
  final route = List<LatLng>.generate(
    scenario.routePointCount,
    (index) =>
        LatLng(10.60 + index * 0.0001, 122.95 + math.sin(index / 12) * 0.001),
    growable: false,
  );
  final restrictions = List<RouteRestriction>.generate(
    scenario.restrictionCount,
    (index) => scenario.firstRestrictionConflicts && index == 0
        ? _restrictionAcrossRoute(index)
        : _restrictionOutsideRoute(index),
    growable: false,
  );
  final expectedResult = scenario.firstRestrictionConflicts ? 0 : null;

  final dartEngine = RouteRestrictionEngine(
    mode: RustMigrationMode.off,
    rustBridge: bridge,
    reporter: (_) {},
  );
  final rustEngine = RouteRestrictionEngine(
    mode: RustMigrationMode.on,
    rustBridge: bridge,
    reporter: (_) {},
  );

  Future<int?> runDart() => dartEngine.firstRouteConflictIndex(
    route: route,
    restrictions: restrictions,
  );
  Future<int?> runRust() => rustEngine.firstRouteConflictIndex(
    route: route,
    restrictions: restrictions,
  );

  int? dartColdFirstCallUs;
  int? rustColdFirstCallUs;
  if (scenario.measureColdStart) {
    dartColdFirstCallUs = await _measureMicroseconds(
      runDart,
      expectedResult: expectedResult,
    );
    rustColdFirstCallUs = await _measureMicroseconds(
      runRust,
      expectedResult: expectedResult,
    );
  }

  for (var index = 0; index < scenario.warmupCount; index++) {
    expect(await runDart(), expectedResult);
    expect(await runRust(), expectedResult);
  }

  final dartSamplesUs = <int>[];
  final rustSamplesUs = <int>[];
  for (var index = 0; index < scenario.sampleCount; index++) {
    if (index.isEven) {
      dartSamplesUs.add(
        await _measureMicroseconds(runDart, expectedResult: expectedResult),
      );
      rustSamplesUs.add(
        await _measureMicroseconds(runRust, expectedResult: expectedResult),
      );
    } else {
      rustSamplesUs.add(
        await _measureMicroseconds(runRust, expectedResult: expectedResult),
      );
      dartSamplesUs.add(
        await _measureMicroseconds(runDart, expectedResult: expectedResult),
      );
    }
  }

  final dartMedianUs = _percentile(dartSamplesUs, 0.5);
  final rustMedianUs = _percentile(rustSamplesUs, 0.5);
  return <String, Object>{
    'scenario': scenario.name,
    'buildMode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'routePoints': scenario.routePointCount,
    'restrictions': scenario.restrictionCount,
    'firstRestrictionConflicts': scenario.firstRestrictionConflicts,
    'samples': scenario.sampleCount,
    'dartMedianUs': dartMedianUs,
    'dartP95Us': _percentile(dartSamplesUs, 0.95),
    'rustMedianUs': rustMedianUs,
    'rustP95Us': _percentile(rustSamplesUs, 0.95),
    'dartToRustMedianRatio': dartMedianUs / rustMedianUs,
    'dartColdFirstCallUs': ?dartColdFirstCallUs,
    'rustColdFirstCallUs': ?rustColdFirstCallUs,
  };
}

Future<int> _measureOperation(Future<void> Function() operation) async {
  final stopwatch = Stopwatch()..start();
  await operation();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

Future<int> _measureMicroseconds(
  Future<int?> Function() operation, {
  required int? expectedResult,
}) async {
  final stopwatch = Stopwatch()..start();
  final result = await operation();
  stopwatch.stop();
  expect(result, expectedResult);
  return stopwatch.elapsedMicroseconds;
}

int _percentile(List<int> samples, double percentile) {
  final sorted = samples.toList(growable: false)..sort();
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}

RouteRestriction _restrictionOutsideRoute(int index) {
  final latitude = 12.0 + (index ~/ 16) * 0.01;
  final longitude = 124.0 + (index % 16) * 0.01;
  final area = <LatLng>[
    LatLng(latitude, longitude),
    LatLng(latitude, longitude + 0.002),
    LatLng(latitude + 0.002, longitude + 0.002),
    LatLng(latitude + 0.002, longitude),
  ];
  return RouteRestriction(
    id: 'benchmark-$index',
    name: 'Benchmark restriction $index',
    type: 'restricted_crossing',
    polygon: area,
    areas: <List<LatLng>>[area],
    isActive: true,
  );
}

RouteRestriction _restrictionAcrossRoute(int index) {
  const area = <LatLng>[
    LatLng(10.599, 122.948),
    LatLng(10.599, 122.952),
    LatLng(10.602, 122.952),
    LatLng(10.602, 122.948),
  ];
  return RouteRestriction(
    id: 'benchmark-$index',
    name: 'Benchmark restriction $index',
    type: 'restricted_crossing',
    polygon: area,
    areas: const <List<LatLng>>[area],
    isActive: true,
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

class _BenchmarkScenario {
  const _BenchmarkScenario({
    required this.name,
    required this.routePointCount,
    required this.restrictionCount,
    required this.warmupCount,
    required this.sampleCount,
    this.firstRestrictionConflicts = false,
    this.measureColdStart = false,
  });

  final String name;
  final int routePointCount;
  final int restrictionCount;
  final int warmupCount;
  final int sampleCount;
  final bool firstRestrictionConflicts;
  final bool measureColdStart;
}
