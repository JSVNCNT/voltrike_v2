import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/services/psgc_compact_index.dart';
import 'package:voltrike_v2/core/services/psgc_index_types.dart';

void main() {
  late Uint8List artifact;
  late PsgcCompactIndex index;
  late List<Map<String, dynamic>> regions;
  late List<Map<String, dynamic>> provinces;
  late List<Map<String, dynamic>> cities;
  late List<Map<String, dynamic>> barangays;

  setUpAll(() async {
    artifact = await File('assets/regionJson/psgc_index_v1.bin').readAsBytes();
    index = PsgcCompactIndex.decode(artifact);
    regions = await _readJson('regions.json');
    provinces = await _readJson('provinces.json');
    cities = await _readJson('cities-municipalities.json');
    barangays = await _readJson('barangays.json');
  });

  test('checked artifact metadata is canonical', () {
    expect(
      readPsgcArtifactMetadata(artifact),
      const PsgcArtifactMetadata(
        formatVersion: 1,
        artifactBytes: 3474156,
        payloadBytes: 3474112,
        payloadChecksumHex: '57417d883f20e124',
        stringCount: 115909,
        counts: PsgcCounts(
          regions: 17,
          provinces: 81,
          cities: 1634,
          barangays: 42046,
        ),
      ),
    );
  });

  test(
    'production Flutter assets include only the compact PSGC artifact',
    () async {
      final pubspec = await File('pubspec.yaml').readAsString();

      expect(
        RegExp(
          r'^\s*-\s+assets/regionJson/psgc_index_v1\.bin\s*$',
          multiLine: true,
        ).hasMatch(pubspec),
        isTrue,
      );
      expect(
        RegExp(
          r'^\s*-\s+assets/regionJson/\s*$',
          multiLine: true,
        ).hasMatch(pubspec),
        isFalse,
        reason: 'The directory declaration would also bundle all raw JSON.',
      );
      for (final source in const <String>[
        'regions.json',
        'provinces.json',
        'cities-municipalities.json',
        'barangays.json',
      ]) {
        expect(pubspec, isNot(contains('assets/regionJson/$source')));
      }
    },
  );

  test('all compact records exactly match canonical JSON and source order', () {
    expect(index.allEntries(PsgcLevel.region), regions);
    expect(index.allEntries(PsgcLevel.province), provinces);
    expect(index.allEntries(PsgcLevel.city), cities);
    expect(index.allEntries(PsgcLevel.barangay), barangays);
  });

  test('parent queries preserve legacy filtering and order', () {
    const regionCode = '010000000';
    const provinceCode = '012800000';
    const municipalityCode = '012801000';

    expect(
      index.entries(PsgcLevel.province, parentCode: regionCode),
      provinces.where((record) => record['regionCode'] == regionCode).toList(),
    );
    expect(
      index.entries(PsgcLevel.city, parentCode: provinceCode),
      cities.where((record) => record['provinceCode'] == provinceCode).toList(),
    );
    expect(
      index.entries(PsgcLevel.barangay, parentCode: municipalityCode),
      barangays
          .where(
            (record) =>
                record['cityCode'] == municipalityCode ||
                record['municipalityCode'] == municipalityCode,
          )
          .toList(),
    );
  });

  test('legacy fuzzy lookup and false-valued fields remain exact', () {
    expect(
      index.findByName(PsgcLevel.city, 'City of Laoag'),
      cities.firstWhere((record) => record['name'] == 'City of Laoag'),
    );
    expect(
      index.findByName(
        PsgcLevel.barangay,
        'Barangay Adams (Pob.)',
        parentCode: '012801000',
      ),
      barangays.first,
    );
    expect(
      index.findByName(PsgcLevel.region, ''),
      regions.first,
      reason: 'The legacy contains-based helper returns the first row for "".',
    );
    expect(index.allEntries(PsgcLevel.barangay).first['cityCode'], isFalse);
    expect(index.allEntries(PsgcLevel.city).first['districtCode'], isFalse);
  });

  test('code lookups match legacy first-match behavior', () {
    expect(index.nameForCode(PsgcLevel.region, '010000000'), 'Ilocos Region');
    expect(index.nameForCode(PsgcLevel.province, '012800000'), 'Ilocos Norte');
    expect(index.nameForCode(PsgcLevel.city, '012801000'), 'Adams');
    expect(index.nameForCode(PsgcLevel.barangay, '012801001'), 'Adams (Pob.)');
    expect(index.nameForCode(PsgcLevel.barangay, 'not-a-code'), isNull);
  });

  test('corruption is rejected before decoding records', () {
    final corrupted = Uint8List.fromList(artifact);
    corrupted[corrupted.length - 1] ^= 1;

    expect(() => PsgcCompactIndex.decode(corrupted), throwsFormatException);
  });
}

Future<List<Map<String, dynamic>>> _readJson(String fileName) async {
  final value = jsonDecode(
    await File('assets/regionJson/$fileName').readAsString(),
  );
  return (value as List)
      .map((record) => Map<String, dynamic>.from(record as Map))
      .toList();
}
