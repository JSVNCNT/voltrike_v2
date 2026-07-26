import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/utils/distance_formatter.dart';

void main() {
  group('DistanceFormatter.compactMeters', () {
    const cases = <({double meters, String label})>[
      (meters: 49.6, label: '50 m'),
      (meters: 123, label: '123 m'),
      (meters: 456, label: '456 m'),
      (meters: 999, label: '999 m'),
      (meters: 1000, label: '1.0 km'),
      (meters: 1250, label: '1.3 km'),
      (meters: 2100, label: '2.1 km'),
    ];

    for (final testCase in cases) {
      test('${testCase.meters} formats as ${testCase.label}', () {
        expect(
          DistanceFormatter.compactMeters(testCase.meters),
          testCase.label,
        );
      });
    }

    test('negative and non-finite values are safe', () {
      expect(DistanceFormatter.compactMeters(-10), '0 m');
      expect(DistanceFormatter.compactMeters(double.nan), '0 m');
    });
  });
}
