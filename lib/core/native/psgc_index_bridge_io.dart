import 'dart:typed_data';

import '../services/psgc_index_metadata.g.dart';
import '../services/psgc_index_types.dart';
import 'generated/api/psgc.dart' as psgc_api;
import 'native_rust_platform.dart';
import 'psgc_index_bridge_contract.dart';
import 'rust_bridge_runtime.dart';

PsgcIndexBridge createPsgcIndexBridge() => GeneratedPsgcIndexBridge();

class GeneratedPsgcIndexBridge implements PsgcIndexBridge {
  bool _ready = false;

  @override
  bool get isSupported => supportsNativeRust;

  @override
  Future<PsgcArtifactMetadata> initialize(Uint8List artifact) async {
    if (!isSupported) {
      throw UnsupportedError(
        'The VolTrike Rust PSGC bridge is unavailable on this platform.',
      );
    }
    await RustBridgeRuntime.ensureInitialized();
    final result = await psgc_api.initializePsgcIndex(artifact: artifact);
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'PSGC initialization',
    );
    final metadata = PsgcArtifactMetadata(
      formatVersion: result.formatVersion,
      artifactBytes: result.artifactBytes,
      payloadBytes: result.payloadBytes,
      payloadChecksumHex: result.payloadChecksumHex,
      stringCount: result.stringCount,
      counts: _counts(result.counts),
    );
    if (metadata != psgcCanonicalMetadata ||
        metadata.artifactBytes != artifact.length) {
      throw StateError(
        'Rust PSGC metadata mismatch: $metadata, '
        'receivedBytes=${artifact.length}.',
      );
    }
    _ready = true;
    return metadata;
  }

  @override
  List<PsgcEntry> entries(PsgcLevel level, {String? parentCode}) {
    _requireReady();
    final result = psgc_api.queryPsgcIndex(
      level: _nativeLevel(level),
      parentCode: parentCode,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'PSGC query',
    );
    return result.entries.map(_entry).toList(growable: false);
  }

  @override
  PsgcEntry? findByName(PsgcLevel level, String name, {String? parentCode}) {
    _requireReady();
    final result = psgc_api.findPsgcByName(
      level: _nativeLevel(level),
      parentCode: parentCode,
      name: name,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'PSGC name lookup',
    );
    final entry = result.entry;
    return entry == null ? null : _entry(entry);
  }

  @override
  String? nameForCode(PsgcLevel level, String code) {
    _requireReady();
    final result = psgc_api.psgcNameForCode(
      level: _nativeLevel(level),
      code: code,
    );
    _throwUnlessOk(
      status: result.status,
      message: result.errorMessage,
      operation: 'PSGC code lookup',
    );
    return result.name;
  }

  void _requireReady() {
    if (!_ready) {
      throw StateError('Rust PSGC index is not initialized.');
    }
  }

  static void _throwUnlessOk({
    required psgc_api.PsgcOperationStatus status,
    required String? message,
    required String operation,
  }) {
    if (status == psgc_api.PsgcOperationStatus.ok) return;
    throw StateError(message ?? 'Rust rejected the $operation ($status).');
  }

  static PsgcCounts _counts(psgc_api.PsgcCounts value) {
    return PsgcCounts(
      regions: value.regions,
      provinces: value.provinces,
      cities: value.cities,
      barangays: value.barangays,
    );
  }

  static psgc_api.PsgcLevel _nativeLevel(PsgcLevel level) {
    return switch (level) {
      PsgcLevel.region => psgc_api.PsgcLevel.region,
      PsgcLevel.province => psgc_api.PsgcLevel.province,
      PsgcLevel.city => psgc_api.PsgcLevel.city,
      PsgcLevel.barangay => psgc_api.PsgcLevel.barangay,
    };
  }

  static PsgcLevel _level(psgc_api.PsgcLevel level) {
    return switch (level) {
      psgc_api.PsgcLevel.region => PsgcLevel.region,
      psgc_api.PsgcLevel.province => PsgcLevel.province,
      psgc_api.PsgcLevel.city => PsgcLevel.city,
      psgc_api.PsgcLevel.barangay => PsgcLevel.barangay,
    };
  }

  static PsgcEntry _entry(psgc_api.PsgcEntry value) {
    return PsgcEntry(
      level: _level(value.level),
      code: value.code,
      name: value.name,
      regionName: value.regionName,
      oldName: value.oldName,
      isCapital: value.isCapital,
      isCity: value.isCity,
      isMunicipality: value.isMunicipality,
      subMunicipalityCode: value.subMunicipalityCode,
      cityCode: value.cityCode,
      municipalityCode: value.municipalityCode,
      districtCode: value.districtCode,
      provinceCode: value.provinceCode,
      regionCode: value.regionCode,
      islandGroupCode: value.islandGroupCode,
      psgc10DigitCode: value.psgc10DigitCode,
    );
  }
}
