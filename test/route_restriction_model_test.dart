import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/data/models/route_restriction.dart';

void main() {
  group('RouteRestriction geometry decoding', () {
    test('parses geometryVersion 2 polygon and area point maps', () {
      final restriction = RouteRestriction.fromMap(
        id: 'restricted-zone',
        data: <String, dynamic>{
          'geometryVersion': 2,
          'name': 'Barangay no-service zone',
          'type': 'no_service_area',
          'geometryType': 'polygon',
          'polygon': <Map<String, double>>[
            <String, double>{'latitude': 10.6601, 'longitude': 122.9401},
            <String, double>{'latitude': 10.6611, 'longitude': 122.9411},
            <String, double>{'latitude': 10.6621, 'longitude': 122.9421},
          ],
          'areas': <Map<String, dynamic>>[
            <String, dynamic>{
              'points': <Map<String, double>>[
                <String, double>{'latitude': 10.6601, 'longitude': 122.9401},
                <String, double>{'latitude': 10.6611, 'longitude': 122.9411},
                <String, double>{'latitude': 10.6621, 'longitude': 122.9421},
              ],
            },
            <String, dynamic>{
              'points': <Map<String, double>>[
                <String, double>{'lat': 10.6701, 'lng': 122.9501},
                <String, double>{'lat': 10.6711, 'lng': 122.9511},
                <String, double>{'lat': 10.6721, 'lng': 122.9521},
              ],
            },
          ],
          'isActive': true,
        },
      );

      expect(restriction.geometryVersion, 2);
      expect(restriction.geometryType, 'polygon');
      expect(restriction.polygon, const <LatLng>[
        LatLng(10.6601, 122.9401),
        LatLng(10.6611, 122.9411),
        LatLng(10.6621, 122.9421),
      ]);
      expect(restriction.areas, hasLength(2));
      expect(restriction.areas[1].first, const LatLng(10.6701, 122.9501));
      expect(restriction.isActive, isTrue);
    });

    test('parses a geometryVersion 2 buffered corridor', () {
      final restriction = RouteRestriction.fromMap(
        id: 'highway-corridor',
        data: <String, dynamic>{
          'geometryVersion': 2,
          'name': 'Highway restriction',
          'type': 'prohibited_highway',
          'geometryType': 'corridor',
          'bufferMeters': 30,
          'coordinates': <Map<String, double>>[
            <String, double>{'latitude': 10.6501, 'longitude': 122.9301},
            <String, double>{'latitude': 10.6601, 'longitude': 122.9401},
          ],
          'areas': <Map<String, dynamic>>[
            <String, dynamic>{
              'points': <Map<String, double>>[
                <String, double>{'latitude': 10.6501, 'longitude': 122.9301},
                <String, double>{'latitude': 10.6601, 'longitude': 122.9401},
              ],
            },
            <String, dynamic>{
              'points': <Map<String, double>>[
                <String, double>{'latitude': 10.6701, 'longitude': 122.9501},
                <String, double>{'latitude': 10.6801, 'longitude': 122.9601},
              ],
            },
          ],
          'isActive': true,
        },
      );

      expect(restriction.geometryVersion, 2);
      expect(restriction.geometryType, 'corridor');
      expect(restriction.bufferMeters, 30);
      expect(restriction.polygon, const <LatLng>[
        LatLng(10.6501, 122.9301),
        LatLng(10.6601, 122.9401),
      ]);
      expect(restriction.areas, hasLength(2));
      expect(restriction.areas.first, restriction.polygon);
      expect(restriction.areas.last, const <LatLng>[
        LatLng(10.6701, 122.9501),
        LatLng(10.6801, 122.9601),
      ]);
    });

    test('retains legacy longitude-latitude tuple decoding', () {
      final restriction = RouteRestriction.fromMap(
        id: 'legacy-zone',
        data: <String, dynamic>{
          'coordinates': <List<double>>[
            <double>[122.9401, 10.6601],
            <double>[122.9411, 10.6611],
          ],
          'areas': <List<List<double>>>[
            <List<double>>[
              <double>[122.9401, 10.6601],
              <double>[122.9411, 10.6611],
            ],
          ],
        },
      );

      expect(restriction.geometryVersion, 1);
      expect(restriction.polygon, const <LatLng>[
        LatLng(10.6601, 122.9401),
        LatLng(10.6611, 122.9411),
      ]);
      expect(restriction.areas.single, restriction.polygon);
    });
  });
}
