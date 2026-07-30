import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/services/polyline_service.dart';

void main() {
  test('decodes the canonical Google polyline example', () {
    final points = PolylineService.decodePolyline(
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    );

    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 0.000001));
    expect(points[0].longitude, closeTo(-120.2, 0.000001));
    expect(points[1].latitude, closeTo(40.7, 0.000001));
    expect(points[1].longitude, closeTo(-120.95, 0.000001));
    expect(points[2].latitude, closeTo(43.252, 0.000001));
    expect(points[2].longitude, closeTo(-126.453, 0.000001));
  });

  test('rejects a coordinate truncated in the encoded stream', () {
    expect(
      () => PolylineService.decodePolyline('_p~iF'),
      throwsA(isA<FormatException>()),
    );
  });

  test('enforces a caller-provided point limit while decoding', () {
    expect(
      () => PolylineService.decodePolyline(
        '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        maxPoints: 2,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects characters outside the Google polyline alphabet', () {
    expect(
      () => PolylineService.decodePolyline('  '),
      throwsA(isA<FormatException>()),
    );
  });
}
