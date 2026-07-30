import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/native/active_route_navigation_engine.dart';
import 'package:voltrike_v2/core/native/rust_migration_mode.dart';
import 'package:voltrike_v2/core/native/rust_navigation_bridge.dart';

void main() {
  const encodedRoute = 'o~b`AotlmV?gEgEgE';

  group('DartActiveRouteProcessor', () {
    test(
      'installs once and derives progress, remaining distance, and heading',
      () async {
        final processor = DartActiveRouteProcessor();
        final install = await processor.installRoute(encodedRoute);

        expect(install.pointCount, 3);
        expect(install.segmentCount, 2);
        expect(install.totalDistanceMeters, greaterThan(150));

        final batch = await processor.processSamples(
          samples: const [
            ActiveRouteGpsSample(
              latitude: 10.67,
              longitude: 122.9505,
              accuracyMeters: 5,
              timestampMillis: 1000,
            ),
          ],
          expectedRouteGeneration: install.routeGeneration,
        );

        expect(batch.acceptedCount, 1);
        expect(batch.rejectedCount, 0);
        final sample = batch.samples.single;
        expect(sample.isAccepted, isTrue);
        expect(sample.distanceFromRouteMeters, lessThan(2));
        expect(sample.routeProgressMeters, greaterThan(30));
        expect(sample.remainingDistanceMeters, greaterThan(50));
        expect(sample.routeHeadingDegrees, inInclusiveRange(0, 360));
      },
    );

    test('matches the shared Rust rejection and batching fixture', () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/fixtures/active_route_navigation_parity.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final processor = DartActiveRouteProcessor();
      final install = await processor.installRoute(
        fixture['encodedPolyline'] as String,
      );
      final samples = (fixture['samples'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (item) => ActiveRouteGpsSample(
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
              accuracyMeters: (item['accuracyMeters'] as num).toDouble(),
              timestampMillis: item['timestampMillis'] as int,
            ),
          )
          .toList();

      final batch = await processor.processSamples(
        samples: samples,
        expectedRouteGeneration: install.routeGeneration,
      );

      expect(batch.acceptedCount, fixture['expectedAcceptedCount']);
      expect(batch.rejectedCount, fixture['expectedRejectedCount']);
      expect(
        batch.samples.map((sample) => sample.disposition.name),
        fixture['expectedDispositions'],
      );
      expect(batch.samples.last.offRouteConfidence, greaterThan(0));
    });

    test(
      'rejects malformed routes and oversized batches without mutation',
      () async {
        final processor = DartActiveRouteProcessor();
        final install = await processor.installRoute(encodedRoute);

        await expectLater(
          processor.installRoute('?'),
          throwsA(isA<FormatException>()),
        );
        await expectLater(
          processor.processSamples(
            samples: List.filled(
              257,
              const ActiveRouteGpsSample(
                latitude: 10.67,
                longitude: 122.95,
                accuracyMeters: 5,
                timestampMillis: 1000,
              ),
            ),
            expectedRouteGeneration: install.routeGeneration,
          ),
          throwsArgumentError,
        );

        final stillActive = await processor.processSamples(
          samples: const [
            ActiveRouteGpsSample(
              latitude: 10.67,
              longitude: 122.95,
              accuracyMeters: 5,
              timestampMillis: 1000,
            ),
          ],
          expectedRouteGeneration: install.routeGeneration,
        );
        expect(stillActive.acceptedCount, 1);
      },
    );
  });

  group('ActiveRouteNavigationEngine rollout', () {
    test('off never invokes Rust', () async {
      final bridge = _FakeRustNavigationBridge();
      final engine = ActiveRouteNavigationEngine(
        mode: RustMigrationMode.off,
        rustBridge: bridge,
      );

      await engine.installRoute(encodedRoute);
      final result = await engine.processSamples(const [
        ActiveRouteGpsSample(
          latitude: 10.67,
          longitude: 122.95,
          accuracyMeters: 5,
          timestampMillis: 1000,
        ),
      ]);
      await engine.clearRoute();

      expect(result.acceptedCount, 1);
      expect(bridge.installCalls, 0);
      expect(bridge.processCalls, 0);
      expect(bridge.clearCalls, 0);
    });

    test('shadow returns Dart and reports a native mismatch', () async {
      final messages = <String>[];
      final bridge = _FakeRustNavigationBridge(
        installResponse: const ActiveRouteInstallResponse(
          routeGeneration: 91,
          pointCount: 99,
          segmentCount: 98,
          totalDistanceMeters: 1,
        ),
        batchResponse: const ActiveRouteBatchResponse(
          routeGeneration: 91,
          acceptedCount: 0,
          rejectedCount: 1,
          samples: [
            ActiveRouteSampleResponse(
              inputIndex: 0,
              disposition: ActiveRouteSampleDisposition.stale,
            ),
          ],
        ),
      );
      final engine = ActiveRouteNavigationEngine(
        mode: RustMigrationMode.shadow,
        rustBridge: bridge,
        reporter: messages.add,
      );

      final install = await engine.installRoute(encodedRoute);
      final batch = await engine.processSamples(const [
        ActiveRouteGpsSample(
          latitude: 10.67,
          longitude: 122.95,
          accuracyMeters: 5,
          timestampMillis: 1000,
        ),
      ]);

      expect(install.pointCount, 3);
      expect(batch.acceptedCount, 1);
      expect(
        messages.where((message) => message.contains('mismatch')),
        hasLength(2),
      );
    });

    test(
      'on returns Rust but falls back to synchronized Dart after failure',
      () async {
        final dart = _CountingDartActiveRouteProcessor();
        final bridge = _FakeRustNavigationBridge(
          installResponse: const ActiveRouteInstallResponse(
            routeGeneration: 42,
            pointCount: 3,
            segmentCount: 2,
            totalDistanceMeters: 999,
          ),
          processError: StateError('native unavailable'),
        );
        final messages = <String>[];
        final engine = ActiveRouteNavigationEngine(
          mode: RustMigrationMode.on,
          rustBridge: bridge,
          dartProcessor: dart,
          reporter: messages.add,
        );

        final install = await engine.installRoute(encodedRoute);
        final batch = await engine.processSamples(const [
          ActiveRouteGpsSample(
            latitude: 10.67,
            longitude: 122.95,
            accuracyMeters: 5,
            timestampMillis: 1000,
          ),
        ]);
        await engine.clearRoute();

        expect(install.routeGeneration, 42);
        expect(batch.acceptedCount, 1);
        expect(messages.single, contains('GPS fallback'));
        expect(bridge.clearCalls, 1);
        expect(dart.installCalls, 1);
        expect(dart.processCalls, 1);
        expect(dart.clearCalls, 1);
      },
    );

    test('on successful path does not duplicate work in Dart', () async {
      final dart = _CountingDartActiveRouteProcessor();
      final bridge = _FakeRustNavigationBridge();
      final engine = ActiveRouteNavigationEngine(
        mode: RustMigrationMode.on,
        rustBridge: bridge,
        dartProcessor: dart,
      );

      await engine.installRoute(encodedRoute);
      final result = await engine.processSamples(const [
        ActiveRouteGpsSample(
          latitude: 10.67,
          longitude: 122.95,
          accuracyMeters: 5,
          timestampMillis: 1000,
        ),
      ]);
      await engine.clearRoute();

      expect(result.acceptedCount, 1);
      expect(dart.installCalls, 0);
      expect(dart.processCalls, 0);
      expect(dart.clearCalls, 0);
      expect(bridge.installCalls, 1);
      expect(bridge.processCalls, 1);
      expect(bridge.clearCalls, 1);
    });

    test(
      'on lazily replays bounded native state before Dart fallback',
      () async {
        final dart = _CountingDartActiveRouteProcessor();
        final bridge = _FakeRustNavigationBridge(
          processError: StateError('native stopped'),
          processErrorAtCall: 2,
        );
        final engine = ActiveRouteNavigationEngine(
          mode: RustMigrationMode.on,
          rustBridge: bridge,
          dartProcessor: dart,
        );

        await engine.installRoute(encodedRoute);
        await engine.processSamples(const [
          ActiveRouteGpsSample(
            latitude: 10.67,
            longitude: 122.95,
            accuracyMeters: 5,
            timestampMillis: 1000,
          ),
        ]);
        final fallback = await engine.processSamples(const [
          ActiveRouteGpsSample(
            latitude: 10.6701,
            longitude: 122.95,
            accuracyMeters: 5,
            timestampMillis: 2000,
          ),
        ]);

        expect(fallback.acceptedCount, 1);
        expect(dart.installCalls, 1);
        expect(dart.processCalls, 2);
        expect(bridge.processCalls, 2);
      },
    );
  });
}

class _CountingDartActiveRouteProcessor extends DartActiveRouteProcessor {
  int installCalls = 0;
  int processCalls = 0;
  int clearCalls = 0;

  @override
  Future<ActiveRouteInstallResponse> installRoute(String encodedPolyline) {
    installCalls++;
    return super.installRoute(encodedPolyline);
  }

  @override
  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  }) {
    processCalls++;
    return super.processSamples(
      samples: samples,
      expectedRouteGeneration: expectedRouteGeneration,
    );
  }

  @override
  Future<ActiveRouteClearResponse> clearRoute(int expectedRouteGeneration) {
    clearCalls++;
    return super.clearRoute(expectedRouteGeneration);
  }
}

class _FakeRustNavigationBridge implements RustNavigationBridge {
  _FakeRustNavigationBridge({
    this.installResponse = const ActiveRouteInstallResponse(
      routeGeneration: 7,
      pointCount: 3,
      segmentCount: 2,
      totalDistanceMeters: 200,
    ),
    this.batchResponse = const ActiveRouteBatchResponse(
      routeGeneration: 7,
      acceptedCount: 1,
      rejectedCount: 0,
      samples: [
        ActiveRouteSampleResponse(
          inputIndex: 0,
          disposition: ActiveRouteSampleDisposition.accepted,
          filteredLatitude: 10.67,
          filteredLongitude: 122.95,
          nearestSegmentIndex: 0,
          distanceFromRouteMeters: 0,
          routeProgressMeters: 0,
          remainingDistanceMeters: 200,
          routeHeadingDegrees: 90,
          offRouteConfidence: 0,
        ),
      ],
    ),
    this.processError,
    this.processErrorAtCall,
  });

  final ActiveRouteInstallResponse installResponse;
  final ActiveRouteBatchResponse batchResponse;
  final Object? processError;
  final int? processErrorAtCall;

  int installCalls = 0;
  int processCalls = 0;
  int clearCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<ActiveRouteInstallResponse> installRoute(
    String encodedPolyline,
  ) async {
    installCalls++;
    return installResponse;
  }

  @override
  Future<ActiveRouteBatchResponse> processSamples({
    required List<ActiveRouteGpsSample> samples,
    required int expectedRouteGeneration,
  }) async {
    processCalls++;
    final error = processError;
    if (error != null &&
        (processErrorAtCall == null || processCalls == processErrorAtCall)) {
      throw error;
    }
    return batchResponse;
  }

  @override
  Future<ActiveRouteClearResponse> clearRoute(
    int expectedRouteGeneration,
  ) async {
    clearCalls++;
    return ActiveRouteClearResponse(routeGeneration: expectedRouteGeneration);
  }
}
