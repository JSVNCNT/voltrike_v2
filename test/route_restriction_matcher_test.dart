import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/services/route_restriction_service.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';

void main() {
  const polygon = <LatLng>[
    LatLng(10.6600, 122.9400),
    LatLng(10.6600, 122.9600),
    LatLng(10.6800, 122.9600),
    LatLng(10.6800, 122.9400),
  ];
  const crossingRoute = <LatLng>[
    LatLng(10.6500, 122.9500),
    LatLng(10.6900, 122.9500),
  ];

  test('legacy highway corridors are retained but never enforced locally', () {
    const corridor = <LatLng>[
      LatLng(10.6600, 122.9500),
      LatLng(10.6800, 122.9500),
    ];
    const restriction = RouteRestriction(
      id: 'legacy-highway',
      name: 'Legacy Highway Corridor',
      type: 'prohibited_highway',
      polygon: corridor,
      areas: <List<LatLng>>[corridor],
      geometryType: 'corridor',
      bufferMeters: 30,
      isActive: true,
    );

    expect(RouteRestrictionMatcher.isEnforcedPolygon(restriction), isFalse);
    expect(
      RouteRestrictionMatcher.routeConflicts(crossingRoute, restriction),
      isFalse,
    );
    expect(
      RouteRestrictionMatcher.pointConflicts(
        const LatLng(10.6700, 122.9500),
        restriction,
      ),
      isFalse,
    );
    expect(
      RouteRestrictionMatcher.distanceToEnforcedPolygonMeters(
        const LatLng(10.6700, 122.9500),
        restriction,
      ),
      double.infinity,
    );
  });

  for (final type in const [
    'no_service_area',
    'restricted_crossing',
    'restricted_driving_area',
  ]) {
    test('$type blocks endpoints and routes through its polygon', () {
      final restriction = RouteRestriction(
        id: type,
        name: type,
        type: type,
        polygon: polygon,
        areas: const <List<LatLng>>[polygon],
        geometryType: 'polygon',
        isActive: true,
      );

      expect(RouteRestrictionMatcher.isEnforcedPolygon(restriction), isTrue);
      expect(
        RouteRestrictionMatcher.pointConflicts(
          const LatLng(10.6700, 122.9500),
          restriction,
        ),
        isTrue,
      );
      expect(
        RouteRestrictionMatcher.routeConflicts(crossingRoute, restriction),
        isTrue,
      );
    });
  }

  test('inactive retained polygons do not block', () {
    const restriction = RouteRestriction(
      id: 'inactive-downtown',
      name: 'Inactive Downtown',
      type: 'no_service_area',
      polygon: polygon,
      areas: <List<LatLng>>[polygon],
      geometryType: 'polygon',
      isActive: false,
    );

    expect(RouteRestrictionMatcher.isEnforcedPolygon(restriction), isFalse);
    expect(
      RouteRestrictionMatcher.pointConflicts(
        const LatLng(10.6700, 122.9500),
        restriction,
      ),
      isFalse,
    );
    expect(
      RouteRestrictionMatcher.routeConflicts(crossingRoute, restriction),
      isFalse,
    );
  });
}
