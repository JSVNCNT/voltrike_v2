import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/services/booking_quote_service.dart';

void main() {
  test('parses an authoritative Go booking quote', () {
    final quote = GoBookingQuote.fromCallable({
      'distanceMeters': 2450,
      'estimatedFare': 65,
      'estimatedDuration': '420s',
      'authoritativeRoutePolyline': '_p~iF~ps|U_ulLnnqC',
      'fareBreakdown': {'baseFare': 20, 'total': 65},
      'fareVersion': 7,
      'isOutsideToda': true,
      'coverageClass': 'cross_boundary',
      'highwayRouteAdvisory': {
        'requestedAvoidHighways': true,
        'routeRestrictionsPartiallyIgnored': false,
      },
      'avoidedRouteRestrictionNames': ['Highway A'],
      'quoteToken': 'opaque-token',
      'expiresAt': '2026-08-04T01:02:03Z',
    });
    expect(quote.distanceMeters, 2450);
    expect(quote.estimatedFare, 65);
    expect(quote.fareVersion, 7);
    expect(quote.isOutsideToda, isTrue);
    expect(quote.routePolicy.avoidedRestrictionNames, ['Highway A']);
    expect(quote.quoteToken, 'opaque-token');
    expect(quote.quoteExpiresAt, DateTime.utc(2026, 8, 4, 1, 2, 3));
  });

  test('bridge sends booking options and returns parsed quote', () async {
    late Map<String, dynamic> captured;
    final bridge = BookingQuoteService(
      quoteRequest: (input) async {
        captured = input;
        return {
          'distanceMeters': 1000,
          'estimatedFare': 20,
          'authoritativeRoutePolyline': 'abc',
          'fareBreakdown': {'total': 20},
          'quoteToken': 'token',
        };
      },
    );
    final quote = await bridge.tryBookingQuote(
      pickup: const LatLng(10.67, 122.95),
      destination: const LatLng(10.68, 122.96),
      additionalPassengers: 2,
      baggageCount: 1,
    );
    expect(quote?.quoteToken, 'token');
    expect(captured['additionalPassengers'], 2);
    expect(captured['baggageCount'], 1);
  });

  test('rejects incomplete quote responses', () {
    expect(
      () => GoBookingQuote.fromCallable({'distanceMeters': 0}),
      throwsA(isA<GoQuoteException>()),
    );
  });
}
