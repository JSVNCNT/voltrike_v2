import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/features/passenger/services/driver_location_listener_service.dart';

void main() {
  test('rejects malformed coordinates and poor accuracy', () {
    expect(
      DriverLocationSample.tryParse({
        'latitude': 91,
        'longitude': 122.95,
        'accuracy': 5,
        'observedAt': 1000,
      }),
      isNull,
    );
    expect(
      DriverLocationSample.tryParse({
        'latitude': 10.67,
        'longitude': 122.95,
        'accuracy': 101,
        'observedAt': 1000,
      }),
      isNull,
    );
    expect(
      DriverLocationSample.tryParse({
        'latitude': '10.67',
        'longitude': 122.95,
        'accuracy': 5,
        'observedAt': 1000,
        'timestamp': 1000,
      }),
      isNull,
    );
  });

  test(
    'uses server publication time for freshness despite device clock skew',
    () {
      final now = DateTime.utc(2026, 7, 30, 1);
      final filter = DriverLocationSampleFilter();
      final parsed = DriverLocationSample.tryParse({
        'latitude': 10.67,
        'longitude': 122.95,
        'accuracy': 5,
        'observedAt': now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
        'timestamp': now.millisecondsSinceEpoch,
      });

      expect(parsed, isNotNull);
      expect(parsed!.observedAt, now.add(const Duration(hours: 8)));
      expect(parsed.publishedAt, now);
      expect(
        filter.evaluate(parsed, now: now),
        DriverLocationSampleDecision.emit,
      );
    },
  );

  test('rejects stale server publications but suppresses repeated samples', () {
    final now = DateTime.utc(2026, 7, 30, 1);
    final filter = DriverLocationSampleFilter();

    DriverLocationSample sample({
      required DateTime observedAt,
      required DateTime publishedAt,
    }) => DriverLocationSample(
      location: const LatLng(10.67, 122.95),
      accuracyMeters: 5,
      observedAt: observedAt,
      publishedAt: publishedAt,
    );

    expect(
      filter.evaluate(
        sample(
          observedAt: now,
          publishedAt: now.subtract(const Duration(minutes: 1)),
        ),
        now: now,
      ),
      DriverLocationSampleDecision.reject,
    );
    expect(
      filter.evaluate(
        sample(observedAt: now, publishedAt: now),
        now: now,
      ),
      DriverLocationSampleDecision.emit,
    );
    expect(
      filter.evaluate(
        sample(observedAt: now, publishedAt: now),
        now: now,
      ),
      DriverLocationSampleDecision.suppress,
    );
  });

  test('sub-meter suppression uses last emitted point cumulatively', () {
    final now = DateTime.utc(2026, 7, 30, 1);
    final filter = DriverLocationSampleFilter();

    DriverLocationSample sample(int seconds, {double latitude = 10.67}) =>
        DriverLocationSample(
          location: LatLng(latitude, 122.95),
          accuracyMeters: 5,
          observedAt: now.add(Duration(seconds: seconds)),
          publishedAt: now,
        );

    expect(
      filter.evaluate(sample(0), now: now),
      DriverLocationSampleDecision.emit,
    );
    expect(
      filter.evaluate(sample(1, latitude: 10.670006), now: now),
      DriverLocationSampleDecision.suppress,
    );
    expect(
      filter.evaluate(sample(2, latitude: 10.670012), now: now),
      DriverLocationSampleDecision.emit,
    );
  });
}
