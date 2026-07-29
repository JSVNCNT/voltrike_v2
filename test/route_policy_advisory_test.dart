import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/services/routes_service.dart';
import 'package:voltrike_v2/data/models/route_policy_advisory.dart';

void main() {
  test('Google request asks for highway avoidance and alternatives', () {
    final request = RoutesService.buildRequest(
      origin: const LatLng(10.67, 122.95),
      destination: const LatLng(10.68, 122.96),
    );

    expect(request['travelMode'], 'DRIVE');
    expect(request['computeAlternativeRoutes'], isTrue);
    expect(
      (request['routeModifiers'] as Map<String, dynamic>)['avoidHighways'],
      isTrue,
    );
  });

  test('parses route-level partially ignored advisory', () {
    final route = RoutesService.parseGoogleRoute({
      'routeToken': 'safe-native-route-token',
      'distanceMeters': 1400,
      'duration': '420s',
      'polyline': {'encodedPolyline': 'abc'},
      'travelAdvisory': {'routeRestrictionsPartiallyIgnored': true},
    });

    expect(route.routePolicy.highwayAvoidanceRequested, isTrue);
    expect(route.routeToken, 'safe-native-route-token');
    expect(route.routePolicy.restrictionsPartiallyIgnored, isTrue);
    expect(
      route.routePolicy.passengerMessage,
      contains('Highways are avoided where possible'),
    );
  });

  test('backend highway advisory aliases are tolerated', () {
    final advisory = RoutePolicyAdvisory.fromMap({
      'requestedAvoidHighways': true,
      'routeRestrictionsPartiallyIgnored': true,
    });

    expect(advisory.highwayAvoidanceRequested, isTrue);
    expect(advisory.restrictionsPartiallyIgnored, isTrue);
  });
}
