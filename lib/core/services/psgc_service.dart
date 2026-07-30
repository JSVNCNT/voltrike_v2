import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../native/psgc_index_bridge.dart';
import '../native/rust_migration_mode.dart';
import 'psgc_compact_index.dart';
import 'psgc_index_metadata.g.dart';
import 'psgc_index_types.dart';

/// Philippine Standard Geographic Code (PSGC) service.
///
/// The canonical JSON files remain generation inputs, but the application
/// loads only the deterministic compact artifact. Rust owns the decoded index
/// in `VOLTRIKE_PSGC_MODE=on`; the compact Dart decoder is the safe fallback.
class PSGCService {
  PSGCService._internal()
    : _assetBundle = rootBundle,
      _nativeBridge = createPsgcIndexBridge(),
      _rustMode = RustMigrationMode.psgcFromEnvironment();

  @visibleForTesting
  PSGCService.forTesting({
    required AssetBundle assetBundle,
    required PsgcIndexBridge nativeBridge,
    RustMigrationMode rustMode = RustMigrationMode.off,
  }) : _assetBundle = assetBundle,
       _nativeBridge = nativeBridge,
       _rustMode = rustMode;

  static final PSGCService _instance = PSGCService._internal();

  factory PSGCService() => _instance;

  static const _artifactPath = 'assets/regionJson/psgc_index_v1.bin';

  final AssetBundle _assetBundle;
  final PsgcIndexBridge _nativeBridge;
  final RustMigrationMode _rustMode;

  PsgcCompactIndex? _dartIndex;
  Uint8List? _compactBytes;
  PsgcCounts _counts = PsgcCounts.empty;
  Future<void>? _initialization;
  bool _nativeActive = false;
  bool _shadowNative = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final pending = _initialization ??= _initialize();
    try {
      await pending;
    } finally {
      if (identical(_initialization, pending)) {
        _initialization = null;
      }
    }
  }

  Future<void> _initialize() async {
    try {
      final artifact = await _loadArtifact();
      final metadata = readPsgcArtifactMetadata(artifact);
      if (metadata != psgcCanonicalMetadata) {
        throw StateError('Unexpected PSGC artifact metadata: $metadata.');
      }
      switch (_rustMode) {
        case RustMigrationMode.off:
          _activateDart(PsgcCompactIndex.decode(artifact));
        case RustMigrationMode.shadow:
          final dartIndex = PsgcCompactIndex.decode(artifact);
          _activateDart(dartIndex);
          await _tryInitializeNative(
            artifact,
            shadow: true,
            expectedMetadata: metadata,
          );
        case RustMigrationMode.on:
          _compactBytes = artifact;
          final initialized = await _tryInitializeNative(
            artifact,
            shadow: false,
            expectedMetadata: metadata,
          );
          if (!initialized) {
            _activateDart(PsgcCompactIndex.decode(artifact));
          }
      }
      _initialized = true;
    } catch (error) {
      debugPrint('PSGC initialization failed: $error');
      rethrow;
    }
  }

  Future<Uint8List> _loadArtifact() async {
    final data = await _assetBundle.load(_artifactPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<bool> _tryInitializeNative(
    Uint8List artifact, {
    required bool shadow,
    required PsgcArtifactMetadata expectedMetadata,
  }) async {
    if (!_nativeBridge.isSupported) {
      return false;
    }
    try {
      final metadata = await _nativeBridge.initialize(artifact);
      if (metadata != expectedMetadata) {
        debugPrint(
          'PSGC Rust metadata mismatch: '
          'Dart $expectedMetadata, Rust $metadata.',
        );
        return false;
      }
      _counts = metadata.counts;
      _shadowNative = shadow;
      _nativeActive = !shadow;
      return true;
    } catch (error) {
      debugPrint('PSGC Rust initialization unavailable; using Dart: $error');
      return false;
    }
  }

  void _activateDart(PsgcCompactIndex index) {
    _dartIndex = index;
    _counts = index.counts;
    _nativeActive = false;
    if (!_shadowNative) {
      _compactBytes = null;
    }
  }

  List<Map<String, dynamic>> getRegions() {
    return List.unmodifiable(_entries(PsgcLevel.region));
  }

  List<Map<String, dynamic>> getProvincesByRegion(String regionCode) {
    return _entries(PsgcLevel.province, parentCode: regionCode);
  }

  List<Map<String, dynamic>> getCitiesByProvince(String provinceCode) {
    return _entries(PsgcLevel.city, parentCode: provinceCode);
  }

  List<Map<String, dynamic>> getBarangaysByCity(String cityCode) {
    return _entries(PsgcLevel.barangay, parentCode: cityCode);
  }

  Map<String, dynamic>? findRegionByName(String name) {
    return _findByName(PsgcLevel.region, name);
  }

  Map<String, dynamic>? findProvinceByName(String name) {
    return _findByName(PsgcLevel.province, name);
  }

  Map<String, dynamic>? findCityByName(String name) {
    return _findByName(PsgcLevel.city, name);
  }

  Map<String, dynamic>? findBarangayByName(String cityCode, String name) {
    return _findByName(PsgcLevel.barangay, name, parentCode: cityCode);
  }

  String? getRegionName(String regionCode) {
    return _nameForCode(PsgcLevel.region, regionCode);
  }

  String? getProvinceName(String provinceCode) {
    return _nameForCode(PsgcLevel.province, provinceCode);
  }

  String? getCityName(String cityCode) {
    return _nameForCode(PsgcLevel.city, cityCode);
  }

  String? getBarangayName(String barangayCode) {
    return _nameForCode(PsgcLevel.barangay, barangayCode);
  }

  List<Map<String, dynamic>> _entries(PsgcLevel level, {String? parentCode}) {
    if (_nativeActive) {
      try {
        return _nativeBridge
            .entries(level, parentCode: parentCode)
            .map((entry) => entry.toLegacyMap())
            .toList();
      } catch (error) {
        _fallBackAfterNativeFailure(error);
      }
    }

    final result =
        _dartIndex?.entries(level, parentCode: parentCode) ??
        const <Map<String, dynamic>>[];
    if (_shadowNative) {
      try {
        final native = _nativeBridge
            .entries(level, parentCode: parentCode)
            .map((entry) => entry.toLegacyMap())
            .toList();
        if (!_mapListsEqual(result, native)) {
          debugPrint(
            'PSGC Rust shadow mismatch for ${level.name} '
            'parent $parentCode.',
          );
        }
      } catch (error) {
        _disableShadow(error);
      }
    }
    return result;
  }

  Map<String, dynamic>? _findByName(
    PsgcLevel level,
    String name, {
    String? parentCode,
  }) {
    if (_nativeActive) {
      try {
        return _nativeBridge
            .findByName(level, name, parentCode: parentCode)
            ?.toLegacyMap();
      } catch (error) {
        _fallBackAfterNativeFailure(error);
      }
    }

    final result = _dartIndex?.findByName(level, name, parentCode: parentCode);
    if (_shadowNative) {
      try {
        final native = _nativeBridge
            .findByName(level, name, parentCode: parentCode)
            ?.toLegacyMap();
        if (!_nullableMapsEqual(result, native)) {
          debugPrint(
            'PSGC Rust shadow name mismatch for ${level.name}: $name.',
          );
        }
      } catch (error) {
        _disableShadow(error);
      }
    }
    return result;
  }

  String? _nameForCode(PsgcLevel level, String code) {
    if (_nativeActive) {
      try {
        return _nativeBridge.nameForCode(level, code);
      } catch (error) {
        _fallBackAfterNativeFailure(error);
      }
    }

    final result = _dartIndex?.nameForCode(level, code);
    if (_shadowNative) {
      try {
        final native = _nativeBridge.nameForCode(level, code);
        if (result != native) {
          debugPrint(
            'PSGC Rust shadow code mismatch for ${level.name}: $code.',
          );
        }
      } catch (error) {
        _disableShadow(error);
      }
    }
    return result;
  }

  void _fallBackAfterNativeFailure(Object error) {
    debugPrint('PSGC Rust query failed; switching to compact Dart: $error');
    _nativeActive = false;
    final bytes = _compactBytes;
    if (bytes == null) {
      throw StateError('PSGC compact fallback bytes are unavailable.');
    }
    _activateDart(PsgcCompactIndex.decode(bytes));
  }

  void _disableShadow(Object error) {
    debugPrint('PSGC Rust shadow query failed: $error');
    _shadowNative = false;
  }

  bool get isInitialized => _initialized;

  bool get isUsingNativeIndex => _nativeActive;

  int get regionCount => _counts.regions;

  int get provinceCount => _counts.provinces;

  int get cityCount => _counts.cities;

  int get barangayCount => _counts.barangays;
}

bool _mapListsEqual(
  List<Map<String, dynamic>> left,
  List<Map<String, dynamic>> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (!_mapsEqual(left[index], right[index])) {
      return false;
    }
  }
  return true;
}

bool _nullableMapsEqual(
  Map<String, dynamic>? left,
  Map<String, dynamic>? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return _mapsEqual(left, right);
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
