import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/native/psgc_index_bridge_contract.dart';
import 'package:voltrike_v2/core/native/rust_migration_mode.dart';
import 'package:voltrike_v2/core/services/psgc_compact_index.dart';
import 'package:voltrike_v2/core/services/psgc_index_types.dart';
import 'package:voltrike_v2/core/services/psgc_service.dart';

void main() {
  late Uint8List artifact;
  late PsgcArtifactMetadata metadata;

  setUpAll(() async {
    artifact = await File('assets/regionJson/psgc_index_v1.bin').readAsBytes();
    metadata = readPsgcArtifactMetadata(artifact);
  });

  test(
    'off mode uses compact Dart index without touching native bridge',
    () async {
      final bundle = _MemoryAssetBundle(artifact);
      final bridge = _FakePsgcBridge(metadata);
      final service = PSGCService.forTesting(
        assetBundle: bundle,
        nativeBridge: bridge,
      );

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(service.isUsingNativeIndex, isFalse);
      expect(bridge.initializeCalls, 0);
      expect(bundle.loadCalls, 1);
      expect(service.regionCount, 17);
      expect(service.provinceCount, 81);
      expect(service.cityCount, 1634);
      expect(service.barangayCount, 42046);
      expect(service.getRegions().first['name'], 'Ilocos Region');
      expect(
        service.getBarangaysByCity('012801000').first['name'],
        'Adams (Pob.)',
      );
    },
  );

  test('on mode keeps the decoded index native-owned', () async {
    final bundle = _MemoryAssetBundle(artifact);
    final bridge = _FakePsgcBridge(metadata);
    final service = PSGCService.forTesting(
      assetBundle: bundle,
      nativeBridge: bridge,
      rustMode: RustMigrationMode.on,
    );

    await service.initialize();

    expect(service.isUsingNativeIndex, isTrue);
    expect(bridge.initializeCalls, 1);
    expect(service.getRegions(), <Map<String, dynamic>>[
      const PsgcEntry(
        level: PsgcLevel.region,
        code: '010000000',
        name: 'Ilocos Region',
        regionName: 'Region I',
        islandGroupCode: 'luzon',
        psgc10DigitCode: '0100000000',
      ).toLegacyMap(),
    ]);
  });

  test(
    'on mode lazily activates compact Dart after a native query failure',
    () async {
      final bridge = _FakePsgcBridge(metadata)..throwQueries = true;
      final service = PSGCService.forTesting(
        assetBundle: _MemoryAssetBundle(artifact),
        nativeBridge: bridge,
        rustMode: RustMigrationMode.on,
      );
      await service.initialize();
      expect(service.isUsingNativeIndex, isTrue);

      final regions = service.getRegions();

      expect(service.isUsingNativeIndex, isFalse);
      expect(regions, hasLength(17));
      expect(regions.first['code'], '010000000');
      expect(regions.last['code'], '150000000');
    },
  );

  test(
    'invalid compact bytes fail closed before either backend starts',
    () async {
      final corrupted = Uint8List.fromList(artifact);
      corrupted[corrupted.length - 1] ^= 1;
      final bridge = _FakePsgcBridge(metadata);
      final service = PSGCService.forTesting(
        assetBundle: _MemoryAssetBundle(corrupted),
        nativeBridge: bridge,
        rustMode: RustMigrationMode.on,
      );

      await expectLater(service.initialize(), throwsFormatException);
      expect(service.isInitialized, isFalse);
      expect(bridge.initializeCalls, 0);
    },
  );
}

class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.bytes);

  final Uint8List bytes;
  int loadCalls = 0;

  @override
  Future<ByteData> load(String key) async {
    loadCalls++;
    if (key != 'assets/regionJson/psgc_index_v1.bin') {
      throw StateError('Unexpected test asset: $key');
    }
    return ByteData.sublistView(bytes);
  }
}

class _FakePsgcBridge implements PsgcIndexBridge {
  _FakePsgcBridge(this.metadata);

  final PsgcArtifactMetadata metadata;
  int initializeCalls = 0;
  bool throwQueries = false;

  @override
  bool get isSupported => true;

  @override
  Future<PsgcArtifactMetadata> initialize(Uint8List artifact) async {
    initializeCalls++;
    return metadata;
  }

  @override
  List<PsgcEntry> entries(PsgcLevel level, {String? parentCode}) {
    _checkQuery();
    if (level != PsgcLevel.region) {
      return const <PsgcEntry>[];
    }
    return const <PsgcEntry>[
      PsgcEntry(
        level: PsgcLevel.region,
        code: '010000000',
        name: 'Ilocos Region',
        regionName: 'Region I',
        islandGroupCode: 'luzon',
        psgc10DigitCode: '0100000000',
      ),
    ];
  }

  @override
  PsgcEntry? findByName(PsgcLevel level, String name, {String? parentCode}) {
    _checkQuery();
    return null;
  }

  @override
  String? nameForCode(PsgcLevel level, String code) {
    _checkQuery();
    return null;
  }

  void _checkQuery() {
    if (throwQueries) {
      throw StateError('simulated native query failure');
    }
  }
}
