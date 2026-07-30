import 'dart:convert';
import 'dart:typed_data';

import 'psgc_index_types.dart';

const _magic = <int>[0x56, 0x50, 0x53, 0x47, 0x43, 0x49, 0x44, 0x58];
const _formatVersion = 1;
const _headerLength = 44;
const _missingString = 0xffffffff;
const _fnvOffsetBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _uint64Mask = 0xffffffffffffffff;
const _maximumArtifactBytes = 16 * 1024 * 1024;
const _maximumStrings = 500000;

PsgcArtifactMetadata readPsgcArtifactMetadata(Uint8List bytes) {
  if (bytes.length < _headerLength) {
    throw const FormatException('PSGC artifact header is truncated.');
  }
  if (bytes.length > _maximumArtifactBytes) {
    throw const FormatException('PSGC artifact exceeds the size limit.');
  }
  for (var index = 0; index < _magic.length; index++) {
    if (bytes[index] != _magic[index]) {
      throw const FormatException('PSGC artifact magic is invalid.');
    }
  }

  final header = ByteData.sublistView(bytes, 0, _headerLength);
  final version = header.getUint32(8, Endian.little);
  if (version != _formatVersion) {
    throw FormatException('Unsupported PSGC artifact version $version.');
  }
  final payloadLength = header.getUint32(12, Endian.little);
  if (payloadLength != bytes.length - _headerLength) {
    throw const FormatException('PSGC artifact length is invalid.');
  }
  final expectedChecksum = header.getUint64(16, Endian.little);
  final actualChecksum = _fnv1a(bytes, _headerLength);
  if (expectedChecksum != actualChecksum) {
    throw const FormatException('PSGC artifact checksum is invalid.');
  }

  final counts = PsgcCounts(
    regions: header.getUint32(24, Endian.little),
    provinces: header.getUint32(28, Endian.little),
    cities: header.getUint32(32, Endian.little),
    barangays: header.getUint32(36, Endian.little),
  );
  final stringCount = header.getUint32(40, Endian.little);
  _validateCounts(
    regionCount: counts.regions,
    provinceCount: counts.provinces,
    cityCount: counts.cities,
    barangayCount: counts.barangays,
    stringCount: stringCount,
  );
  return PsgcArtifactMetadata(
    formatVersion: version,
    artifactBytes: bytes.length,
    payloadBytes: payloadLength,
    payloadChecksumHex: expectedChecksum.toRadixString(16).padLeft(16, '0'),
    stringCount: stringCount,
    counts: counts,
  );
}

class PsgcCompactIndex {
  PsgcCompactIndex._({
    required List<PsgcEntry> regions,
    required List<PsgcEntry> provinces,
    required List<PsgcEntry> cities,
    required List<PsgcEntry> barangays,
  }) : _regions = List.unmodifiable(regions),
       _provinces = List.unmodifiable(provinces),
       _cities = List.unmodifiable(cities),
       _barangays = List.unmodifiable(barangays) {
    _provincesByRegion = _groupBy(_provinces, (entry) => entry.regionCode);
    _citiesByProvince = _groupBy(_cities, (entry) => entry.provinceCode);
    _barangaysByCity = <String, List<PsgcEntry>>{};
    for (final entry in _barangays) {
      _addToGroup(_barangaysByCity, entry.cityCode, entry);
      if (entry.municipalityCode != entry.cityCode) {
        _addToGroup(_barangaysByCity, entry.municipalityCode, entry);
      }
    }
    _byCode = <PsgcLevel, Map<String, PsgcEntry>>{
      PsgcLevel.region: _indexByCode(_regions),
      PsgcLevel.province: _indexByCode(_provinces),
      PsgcLevel.city: _indexByCode(_cities),
      PsgcLevel.barangay: _indexByCode(_barangays),
    };
  }

  factory PsgcCompactIndex.decode(Uint8List bytes) {
    final metadata = readPsgcArtifactMetadata(bytes);
    final regionCount = metadata.counts.regions;
    final provinceCount = metadata.counts.provinces;
    final cityCount = metadata.counts.cities;
    final barangayCount = metadata.counts.barangays;
    final stringCount = metadata.stringCount;

    final reader = _BinaryReader(bytes, _headerLength);
    final strings = List<String>.generate(
      stringCount,
      (_) => reader.readString(),
      growable: false,
    );
    final resolver = _StringResolver(strings);

    final regions = List<PsgcEntry>.generate(regionCount, (_) {
      return PsgcEntry(
        level: PsgcLevel.region,
        code: resolver.required(reader.readUint32()),
        name: resolver.required(reader.readUint32()),
        regionName: resolver.required(reader.readUint32()),
        islandGroupCode: resolver.required(reader.readUint32()),
        psgc10DigitCode: resolver.required(reader.readUint32()),
      );
    }, growable: false);

    final provinces = List<PsgcEntry>.generate(provinceCount, (_) {
      return PsgcEntry(
        level: PsgcLevel.province,
        code: resolver.required(reader.readUint32()),
        name: resolver.required(reader.readUint32()),
        regionCode: resolver.required(reader.readUint32()),
        islandGroupCode: resolver.required(reader.readUint32()),
        psgc10DigitCode: resolver.required(reader.readUint32()),
      );
    }, growable: false);

    final cities = List<PsgcEntry>.generate(cityCount, (_) {
      final code = resolver.required(reader.readUint32());
      final name = resolver.required(reader.readUint32());
      final oldName = resolver.required(reader.readUint32());
      final flags = reader.readUint8();
      if (flags & ~7 != 0) {
        throw const FormatException('PSGC city flags are invalid.');
      }
      return PsgcEntry(
        level: PsgcLevel.city,
        code: code,
        name: name,
        oldName: oldName,
        isCapital: flags & 1 != 0,
        isCity: flags & 2 != 0,
        isMunicipality: flags & 4 != 0,
        provinceCode: resolver.optional(reader.readUint32()),
        districtCode: resolver.optional(reader.readUint32()),
        regionCode: resolver.required(reader.readUint32()),
        islandGroupCode: resolver.required(reader.readUint32()),
        psgc10DigitCode: resolver.required(reader.readUint32()),
      );
    }, growable: false);

    final barangays = List<PsgcEntry>.generate(barangayCount, (_) {
      return PsgcEntry(
        level: PsgcLevel.barangay,
        code: resolver.required(reader.readUint32()),
        name: resolver.required(reader.readUint32()),
        oldName: resolver.required(reader.readUint32()),
        subMunicipalityCode: resolver.optional(reader.readUint32()),
        cityCode: resolver.optional(reader.readUint32()),
        municipalityCode: resolver.optional(reader.readUint32()),
        districtCode: resolver.optional(reader.readUint32()),
        provinceCode: resolver.optional(reader.readUint32()),
        regionCode: resolver.required(reader.readUint32()),
        islandGroupCode: resolver.required(reader.readUint32()),
        psgc10DigitCode: resolver.required(reader.readUint32()),
      );
    }, growable: false);

    if (!reader.isAtEnd) {
      throw const FormatException('PSGC artifact contains trailing bytes.');
    }
    return PsgcCompactIndex._(
      regions: regions,
      provinces: provinces,
      cities: cities,
      barangays: barangays,
    );
  }

  final List<PsgcEntry> _regions;
  final List<PsgcEntry> _provinces;
  final List<PsgcEntry> _cities;
  final List<PsgcEntry> _barangays;
  late final Map<String, List<PsgcEntry>> _provincesByRegion;
  late final Map<String, List<PsgcEntry>> _citiesByProvince;
  late final Map<String, List<PsgcEntry>> _barangaysByCity;
  late final Map<PsgcLevel, Map<String, PsgcEntry>> _byCode;

  PsgcCounts get counts => PsgcCounts(
    regions: _regions.length,
    provinces: _provinces.length,
    cities: _cities.length,
    barangays: _barangays.length,
  );

  List<Map<String, dynamic>> entries(PsgcLevel level, {String? parentCode}) {
    final records = switch (level) {
      PsgcLevel.region => _regions,
      PsgcLevel.province =>
        _provincesByRegion[parentCode] ?? const <PsgcEntry>[],
      PsgcLevel.city => _citiesByProvince[parentCode] ?? const <PsgcEntry>[],
      PsgcLevel.barangay => _barangaysByCity[parentCode] ?? const <PsgcEntry>[],
    };
    return records.map((entry) => entry.toLegacyMap()).toList();
  }

  List<Map<String, dynamic>> allEntries(PsgcLevel level) {
    return _allForLevel(level).map((entry) => entry.toLegacyMap()).toList();
  }

  Map<String, dynamic>? findByName(
    PsgcLevel level,
    String name, {
    String? parentCode,
  }) {
    final records = level == PsgcLevel.barangay
        ? _barangaysByCity[parentCode] ?? const <PsgcEntry>[]
        : _allForLevel(level);
    final search = level == PsgcLevel.barangay
        ? normalizePsgcBarangayName(name)
        : normalizePsgcName(name);
    for (final entry in records) {
      final normalized = level == PsgcLevel.barangay
          ? normalizePsgcBarangayName(entry.name)
          : normalizePsgcName(entry.name);
      if (normalized.contains(search) || search.contains(normalized)) {
        return entry.toLegacyMap();
      }
    }
    return null;
  }

  String? nameForCode(PsgcLevel level, String code) {
    return _byCode[level]?[code]?.name;
  }

  List<PsgcEntry> _allForLevel(PsgcLevel level) {
    return switch (level) {
      PsgcLevel.region => _regions,
      PsgcLevel.province => _provinces,
      PsgcLevel.city => _cities,
      PsgcLevel.barangay => _barangays,
    };
  }
}

Map<String, List<PsgcEntry>> _groupBy(
  List<PsgcEntry> entries,
  String? Function(PsgcEntry) parentCode,
) {
  final groups = <String, List<PsgcEntry>>{};
  for (final entry in entries) {
    _addToGroup(groups, parentCode(entry), entry);
  }
  return groups;
}

void _addToGroup(
  Map<String, List<PsgcEntry>> groups,
  String? parentCode,
  PsgcEntry entry,
) {
  if (parentCode != null) {
    (groups[parentCode] ??= <PsgcEntry>[]).add(entry);
  }
}

Map<String, PsgcEntry> _indexByCode(List<PsgcEntry> entries) {
  final result = <String, PsgcEntry>{};
  for (final entry in entries) {
    result.putIfAbsent(entry.code, () => entry);
  }
  return result;
}

void _validateCounts({
  required int regionCount,
  required int provinceCount,
  required int cityCount,
  required int barangayCount,
  required int stringCount,
}) {
  if (regionCount > 100 ||
      provinceCount > 500 ||
      cityCount > 10000 ||
      barangayCount > 100000 ||
      stringCount > _maximumStrings) {
    throw const FormatException('PSGC artifact counts exceed safety limits.');
  }
}

int _fnv1a(Uint8List bytes, int start) {
  var hash = _fnvOffsetBasis;
  for (var index = start; index < bytes.length; index++) {
    hash ^= bytes[index];
    hash = (hash * _fnvPrime) & _uint64Mask;
  }
  return hash;
}

class _StringResolver {
  const _StringResolver(this._strings);

  final List<String> _strings;

  String required(int id) {
    if (id == _missingString || id >= _strings.length) {
      throw const FormatException('PSGC artifact string id is invalid.');
    }
    return _strings[id];
  }

  String? optional(int id) {
    if (id == _missingString) {
      return null;
    }
    return required(id);
  }
}

class _BinaryReader {
  _BinaryReader(this._bytes, this._offset)
    : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset;

  bool get isAtEnd => _offset == _bytes.length;

  int readUint8() {
    _require(1);
    return _bytes[_offset++];
  }

  int readUint32() {
    _require(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String readString() {
    final length = readUint32();
    _require(length);
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
      allowMalformed: false,
    );
    _offset += length;
    return value;
  }

  void _require(int byteCount) {
    if (byteCount < 0 || byteCount > _bytes.length - _offset) {
      throw const FormatException('PSGC artifact is truncated.');
    }
  }
}
