import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';
import 'package:voltrike_v2/features/driver/restrictions/driver_restriction_monitor.dart';

void main() {
  final restriction = RouteRestriction(
    id: 'downtown',
    name: 'Downtown Restricted Area',
    type: 'no_service_area',
    polygon: const [
      LatLng(10, 122),
      LatLng(10, 122.001),
      LatLng(10.001, 122.001),
      LatLng(10.001, 122),
    ],
    areas: const [
      [
        LatLng(10, 122),
        LatLng(10, 122.001),
        LatLng(10.001, 122.001),
        LatLng(10.001, 122),
      ],
    ],
    isActive: true,
  );

  test('requires distinct GPS timestamps for approach, entry, and exit', () {
    final engine = DriverRestrictionTransitionEngine();
    final base = DateTime.utc(2026, 7, 30, 1);

    DriverRestrictionTransition? sample(
      LatLng point,
      int seconds, {
      DateTime? observedAt,
    }) {
      final observed = observedAt ?? base.add(Duration(seconds: seconds));
      return engine.evaluate(
        point: point,
        accuracyMeters: 8,
        observedAt: observed,
        now: observed.add(const Duration(seconds: 1)),
        restrictions: [restriction],
      );
    }

    const approaching = LatLng(10.0005, 122.00145);
    expect(sample(approaching, 0), isNull);
    expect(sample(approaching, 1, observedAt: base), isNull);
    final approach = sample(approaching, 2);
    expect(approach?.current.phase, DriverRestrictionPhase.approaching);

    const inside = LatLng(10.0005, 122.0005);
    expect(sample(inside, 3), isNull);
    expect(
      sample(inside, 4, observedAt: base.add(const Duration(seconds: 3))),
      isNull,
    );
    final entry = sample(inside, 5);
    expect(entry?.entered, isTrue);
    expect(entry?.shouldAlert, isTrue);

    const outside = LatLng(10.0005, 122.003);
    expect(sample(outside, 6), isNull);
    expect(
      sample(outside, 7, observedAt: base.add(const Duration(seconds: 6))),
      isNull,
    );
    final exit = sample(outside, 8);
    expect(exit?.exited, isTrue);
    expect(exit?.current.phase, DriverRestrictionPhase.clear);
  });

  test('ignores inaccurate samples and legacy highway corridors', () {
    final engine = DriverRestrictionTransitionEngine();
    final now = DateTime.utc(2026, 7, 30, 1);
    final inaccurate = engine.evaluate(
      point: const LatLng(10.0005, 122.0005),
      accuracyMeters: 80,
      observedAt: now,
      now: now,
      restrictions: [restriction],
    );
    expect(inaccurate, isNull);
    expect(engine.current.phase, DriverRestrictionPhase.clear);

    final corridor = RouteRestriction(
      id: 'legacy-highway',
      name: 'Legacy highway',
      type: 'prohibited_highway',
      polygon: const [LatLng(10, 122), LatLng(10.001, 122.001)],
      areas: const [
        [LatLng(10, 122), LatLng(10.001, 122.001)],
      ],
      geometryType: 'corridor',
      bufferMeters: 30,
      isActive: true,
    );
    expect(
      engine.evaluate(
        point: const LatLng(10.0005, 122.0005),
        accuracyMeters: 5,
        observedAt: now.add(const Duration(seconds: 1)),
        now: now.add(const Duration(seconds: 1)),
        restrictions: [corridor],
      ),
      isNull,
    );
    expect(engine.current.phase, DriverRestrictionPhase.clear);
  });
}
