import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/driver_violation_case.dart';

void main() {
  test('parses backend evidence, location accuracy, and responding status', () {
    final violation = DriverViolationCase.fromMap(
      id: 'violation_1',
      data: {
        'driverId': 'driver_1',
        'status': 'responding',
        'restrictionId': 'downtown',
        'restrictionName': 'Downtown Restricted Area',
        'restrictionType': 'no_service_area',
        'eventLocation': {
          'latitude': 10.67,
          'longitude': 122.95,
          'accuracy': 7.5,
        },
        'source': 'driver_reported_gps_server_polygon_match',
        'confidence':
            'two_fresh_driver_reported_gps_fixes_server_geometry_match',
        'occurredAt': DateTime.utc(2026, 7, 30),
      },
    );

    expect(violation.isOpen, isTrue);
    expect(violation.accuracyMeters, 7.5);
    expect(violation.source, 'driver_reported_gps_server_polygon_match');
    expect(violation.eventLocation.latitude, 10.67);
  });
}
