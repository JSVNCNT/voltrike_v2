import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/driver.dart';

void main() {
  test('driver rating aggregate supports current and legacy profiles', () {
    final current = Driver.fromMap({
      'uid': 'driver-1',
      'rating': 4.75,
      'ratingCount': 8,
      'completedTrips': 12,
      'totalEarnings': 1200,
    });
    final legacy = Driver.fromMap({'uid': 'driver-2', 'rating': 4.5});

    expect(current.rating, 4.75);
    expect(current.ratingCount, 8);
    expect(current.toMap()['ratingCount'], 8);
    expect(legacy.ratingCount, 0);
  });
}
