import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/services/places_service.dart';

void main() {
  group('PlacesService proximity policy', () {
    test(
      'strictly includes ten kilometres and excludes anything beyond it',
      () {
        expect(PlacesService.isWithinSearchRadius(0), isTrue);
        expect(PlacesService.isWithinSearchRadius(10000), isTrue);
        expect(PlacesService.isWithinSearchRadius(10000.1), isFalse);
        expect(PlacesService.isWithinSearchRadius(-1), isFalse);
      },
    );

    test(
      'GPS proximity is calculated dynamically from the supplied origin',
      () {
        final shortDistance = PlacesService.proximityMeters(
          10.6765,
          122.9509,
          10.6770,
          122.9509,
        );
        final longerDistance = PlacesService.proximityMeters(
          10.6765,
          122.9509,
          10.6865,
          122.9509,
        );

        expect(shortDistance, greaterThan(0));
        expect(longerDistance, greaterThan(shortDistance));
      },
    );
  });
}
