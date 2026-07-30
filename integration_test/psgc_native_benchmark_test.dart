import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voltrike_v2/core/native/psgc_index_bridge.dart';
import 'package:voltrike_v2/core/services/psgc_compact_index.dart';
import 'package:voltrike_v2/core/services/psgc_index_types.dart';

const _legacyBaseUrl = String.fromEnvironment('PSGC_BENCHMARK_BASE_URL');
const _queryParentCode = '063022000';
const _queryIterations = 100;
const _lookupIterations = 1000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'legacy JSON, compact Dart, and native Rust PSGC parity/benchmark',
    (tester) async {
      final bridge = createPsgcIndexBridge();
      expect(
        bridge.isSupported,
        isTrue,
        reason: 'Run this benchmark on the Android physical device.',
      );

      final rawJson = <String, String>{};
      for (final fileName in const <String>[
        'regions.json',
        'provinces.json',
        'cities-municipalities.json',
        'barangays.json',
      ]) {
        rawJson[fileName] = await _download('$_legacyBaseUrl/$fileName');
      }
      final rssAfterLegacyDownload = ProcessInfo.currentRss;

      final legacyWatch = Stopwatch()..start();
      final legacyRegions = _decode(rawJson['regions.json']!);
      final legacyProvinces = _decode(rawJson['provinces.json']!);
      final legacyCities = _decode(rawJson['cities-municipalities.json']!);
      final legacyBarangays = _decode(rawJson['barangays.json']!);
      legacyWatch.stop();
      final rssAfterLegacyDecode = ProcessInfo.currentRss;
      expect(
        <int>[
          legacyRegions.length,
          legacyProvinces.length,
          legacyCities.length,
          legacyBarangays.length,
        ],
        <int>[17, 81, 1634, 42046],
      );

      final artifactData = await rootBundle.load(
        'assets/regionJson/psgc_index_v1.bin',
      );
      final artifact = artifactData.buffer.asUint8List(
        artifactData.offsetInBytes,
        artifactData.lengthInBytes,
      );
      final expectedMetadata = readPsgcArtifactMetadata(artifact);
      final rssAfterArtifactLoad = ProcessInfo.currentRss;

      final dartWatch = Stopwatch()..start();
      final dartIndex = PsgcCompactIndex.decode(artifact);
      dartWatch.stop();
      final rssAfterDartInit = ProcessInfo.currentRss;

      final rustWatch = Stopwatch()..start();
      final rustMetadata = await bridge.initialize(artifact);
      rustWatch.stop();
      final rssAfterRustInit = ProcessInfo.currentRss;
      expect(rustMetadata, expectedMetadata);

      final expectedBarangays = legacyBarangays
          .where(
            (entry) =>
                entry['cityCode'] == _queryParentCode ||
                entry['municipalityCode'] == _queryParentCode,
          )
          .toList();
      final dartBarangays = dartIndex.entries(
        PsgcLevel.barangay,
        parentCode: _queryParentCode,
      );
      final rustBarangays = bridge
          .entries(PsgcLevel.barangay, parentCode: _queryParentCode)
          .map((entry) => entry.toLegacyMap())
          .toList();
      expect(dartBarangays, expectedBarangays);
      expect(rustBarangays, expectedBarangays);

      final legacyQueryMicros = _measureSync(() {
        for (var run = 0; run < _queryIterations; run++) {
          legacyBarangays
              .where(
                (entry) =>
                    entry['cityCode'] == _queryParentCode ||
                    entry['municipalityCode'] == _queryParentCode,
              )
              .toList();
        }
      });
      final dartQueryMicros = _measureSync(() {
        for (var run = 0; run < _queryIterations; run++) {
          dartIndex.entries(PsgcLevel.barangay, parentCode: _queryParentCode);
        }
      });
      final rustQueryMicros = _measureSync(() {
        for (var run = 0; run < _queryIterations; run++) {
          bridge.entries(PsgcLevel.barangay, parentCode: _queryParentCode);
        }
      });
      final legacyLookupMicros = _measureSync(() {
        for (var run = 0; run < _lookupIterations; run++) {
          legacyBarangays.firstWhere((entry) => entry['code'] == '063022001');
        }
      });
      final dartLookupMicros = _measureSync(() {
        for (var run = 0; run < _lookupIterations; run++) {
          dartIndex.nameForCode(PsgcLevel.barangay, '063022001');
        }
      });
      final rustLookupMicros = _measureSync(() {
        for (var run = 0; run < _lookupIterations; run++) {
          bridge.nameForCode(PsgcLevel.barangay, '063022001');
        }
      });

      final result = <String, Object>{
        'device': Platform.operatingSystem,
        'artifactBytes': artifact.length,
        'legacyJsonBytes': rawJson.values.fold<int>(
          0,
          (total, value) => total + utf8.encode(value).length,
        ),
        'payloadFnv1a': expectedMetadata.payloadChecksumHex,
        'counts': <int>[17, 81, 1634, 42046],
        'legacyDecodeMicros': legacyWatch.elapsedMicroseconds,
        'compactDartInitMicros': dartWatch.elapsedMicroseconds,
        'nativeRustInitMicros': rustWatch.elapsedMicroseconds,
        'rssAfterLegacyDownloadBytes': rssAfterLegacyDownload,
        'rssAfterLegacyDecodeBytes': rssAfterLegacyDecode,
        'legacyDecodeRssDeltaBytes':
            rssAfterLegacyDecode - rssAfterLegacyDownload,
        'rssAfterArtifactLoadBytes': rssAfterArtifactLoad,
        'artifactLoadRssDeltaBytes':
            rssAfterArtifactLoad - rssAfterLegacyDecode,
        'rssAfterCompactDartInitBytes': rssAfterDartInit,
        'compactDartInitRssDeltaBytes': rssAfterDartInit - rssAfterArtifactLoad,
        'rssAfterNativeRustInitBytes': rssAfterRustInit,
        'nativeRustInitRssDeltaBytes': rssAfterRustInit - rssAfterDartInit,
        'queryParent': _queryParentCode,
        'queryResultCount': expectedBarangays.length,
        'queryIterations': _queryIterations,
        'legacyQueryMicros': legacyQueryMicros,
        'compactDartQueryMicros': dartQueryMicros,
        'nativeRustQueryMicros': rustQueryMicros,
        'lookupIterations': _lookupIterations,
        'legacyLookupMicros': legacyLookupMicros,
        'compactDartLookupMicros': dartLookupMicros,
        'nativeRustLookupMicros': rustLookupMicros,
      };
      // This stable prefix lets the host runner retain a machine-readable row.
      // ignore: avoid_print
      print('PSGC_BENCHMARK ${jsonEncode(result)}');
    },
    skip: _legacyBaseUrl.isEmpty,
  );
}

Future<String> _download(String url) async {
  Object? lastError;
  for (var attempt = 0; attempt < 20; attempt++) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'PSGC benchmark server returned ${response.statusCode}.',
          uri: Uri.parse(url),
        );
      }
      return await response.transform(utf8.decoder).join();
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      client.close(force: true);
    }
  }
  throw StateError(
    'PSGC benchmark server remained unavailable after retries: $lastError',
  );
}

List<Map<String, dynamic>> _decode(String source) {
  return (jsonDecode(source) as List)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
}

int _measureSync(void Function() action) {
  final watch = Stopwatch()..start();
  action();
  watch.stop();
  return watch.elapsedMicroseconds;
}
