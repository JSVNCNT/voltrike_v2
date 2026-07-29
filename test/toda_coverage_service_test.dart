import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/services/toda_coverage_service.dart';

void main() {
  group('TODA coverage parsing', () {
    test('parses Firestore-safe area and point maps', () {
      final zone = TodaCoverageZone.fromMap(
        documentId: 'toda-a',
        data: {
          'todaId': 'toda-a',
          'areas': [
            {
              'points': [
                {'latitude': 10.66, 'longitude': 122.94},
                {'latitude': 10.66, 'longitude': 122.96},
                {'latitude': 10.68, 'longitude': 122.96},
                {'latitude': 10.68, 'longitude': 122.94},
              ],
            },
            {
              'points': [
                {'lat': 10.70, 'lng': 122.98},
                {'lat': 10.70, 'lng': 123.00},
                {'lat': 10.72, 'lng': 123.00},
                {'lat': 10.72, 'lng': 122.98},
              ],
            },
          ],
        },
      );

      expect(zone, isNotNull);
      expect(zone!.areas, hasLength(2));
      expect(zone.contains(const LatLng(10.67, 122.95)), isTrue);
      expect(zone.contains(const LatLng(10.71, 122.99)), isTrue);
      expect(zone.contains(const LatLng(10.69, 122.97)), isFalse);
    });

    test('parses legacy longitude-latitude arrays and polygon fallback', () {
      final multiArea = TodaCoverageZone.fromMap(
        documentId: 'legacy-multi',
        data: {
          'areas': [
            [
              [122.94, 10.66],
              [122.96, 10.66],
              [122.96, 10.68],
              [122.94, 10.68],
              [122.94, 10.66],
            ],
          ],
        },
      );
      final polygon = TodaCoverageZone.fromMap(
        documentId: 'legacy-polygon',
        data: {
          'polygon': [
            [122.97, 10.66],
            [122.99, 10.66],
            [122.99, 10.68],
            [122.97, 10.68],
          ],
        },
      );

      expect(multiArea, isNotNull);
      expect(multiArea!.areas.single, hasLength(4));
      expect(multiArea.contains(const LatLng(10.67, 122.95)), isTrue);
      expect(polygon, isNotNull);
      expect(polygon!.contains(const LatLng(10.67, 122.98)), isTrue);
    });

    test('rejects inactive, malformed, and out-of-range coverage', () {
      expect(
        TodaCoverageZone.fromMap(
          documentId: 'inactive',
          data: {'isActive': false, 'polygon': _legacySquare(122.94, 10.66)},
        ),
        isNull,
      );
      expect(
        TodaCoverageZone.fromMap(
          documentId: 'malformed',
          data: {
            'polygon': [
              [122.94, 10.66],
              [122.96, 10.66],
            ],
          },
        ),
        isNull,
      );
      expect(
        TodaCoverageZone.fromMap(
          documentId: 'invalid-coordinate',
          data: {
            'polygon': [
              [122.94, 100],
              [122.96, 100],
              [122.96, 101],
            ],
          },
        ),
        isNull,
      );
    });
  });

  group('TODA trip classification', () {
    final todaA = _zone('toda-a', 122.94, 10.66);
    final todaB = _zone('toda-b', 122.97, 10.66);

    test('same-zone trip has no outside surcharge', () {
      final decision = TodaCoverageService.classify(
        pickup: const LatLng(10.665, 122.945),
        destination: const LatLng(10.675, 122.955),
        zones: [todaA, todaB],
      );

      expect(decision.status, TodaTripCoverageStatus.sameZone);
      expect(decision.pickupAllowed, isTrue);
      expect(decision.isOutsideToda, isFalse);
      expect(decision.serviceTodaId, 'toda-a');
    });

    test('destination outside the pickup zone is cross-boundary', () {
      final outsideAll = TodaCoverageService.classify(
        pickup: const LatLng(10.67, 122.95),
        destination: const LatLng(10.70, 123.02),
        zones: [todaA, todaB],
      );
      final differentZone = TodaCoverageService.classify(
        pickup: const LatLng(10.67, 122.95),
        destination: const LatLng(10.67, 122.98),
        zones: [todaA, todaB],
      );

      for (final decision in [outsideAll, differentZone]) {
        expect(decision.status, TodaTripCoverageStatus.crossBoundary);
        expect(decision.pickupAllowed, isTrue);
        expect(decision.isOutsideToda, isTrue);
        expect(decision.serviceTodaId, 'toda-a');
      }
    });

    test('configured pickup outside every zone is blocked', () {
      final decision = TodaCoverageService.classify(
        pickup: const LatLng(10.70, 123.02),
        destination: const LatLng(10.67, 122.95),
        zones: [todaA, todaB],
      );

      expect(decision.status, TodaTripCoverageStatus.pickupOutside);
      expect(decision.pickupAllowed, isFalse);
      expect(decision.isOutsideToda, isFalse);
      expect(decision.destinationTodaIds, ['toda-a']);
    });

    test('missing valid coverage remains available for pilot testing', () {
      final decision = TodaCoverageService.classify(
        pickup: const LatLng(10.70, 123.02),
        destination: const LatLng(10.71, 123.03),
        zones: const [],
      );

      expect(decision.status, TodaTripCoverageStatus.unconfigured);
      expect(decision.pickupAllowed, isTrue);
      expect(decision.isOutsideToda, isFalse);
      expect(decision.serviceTodaId, isNull);
    });

    test('polygon boundary counts as inside', () {
      final decision = TodaCoverageService.classify(
        pickup: const LatLng(10.66, 122.95),
        destination: const LatLng(10.67, 122.95),
        zones: [todaA],
      );

      expect(decision.status, TodaTripCoverageStatus.sameZone);
    });

    test(
      'injected loader is reusable without Firebase initialization',
      () async {
        var loadCount = 0;
        final service = TodaCoverageService(
          loader: () async {
            loadCount++;
            return [todaA];
          },
        );

        final first = await service.classifyTrip(
          pickup: const LatLng(10.67, 122.95),
          destination: const LatLng(10.675, 122.955),
        );
        final second = await service.classifyTrip(
          pickup: const LatLng(10.67, 122.95),
          destination: const LatLng(10.70, 123.02),
        );

        expect(first.status, TodaTripCoverageStatus.sameZone);
        expect(second.status, TodaTripCoverageStatus.crossBoundary);
        expect(loadCount, 1);
      },
    );
  });
}

TodaCoverageZone _zone(String todaId, double west, double south) {
  return TodaCoverageZone.fromMap(
    documentId: todaId,
    data: {'polygon': _legacySquare(west, south)},
  )!;
}

List<List<double>> _legacySquare(double west, double south) {
  return [
    [west, south],
    [west + 0.02, south],
    [west + 0.02, south + 0.02],
    [west, south + 0.02],
  ];
}
