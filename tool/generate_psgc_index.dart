import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _magic = <int>[0x56, 0x50, 0x53, 0x47, 0x43, 0x49, 0x44, 0x58];
const _formatVersion = 1;
const _headerLength = 44;
const _missingString = 0xffffffff;
const _fnvOffsetBasis = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;
const _uint64Mask = 0xffffffffffffffff;

Future<void> main(List<String> arguments) async {
  final unknownArguments = arguments
      .where((argument) => argument != '--check')
      .toList();
  if (unknownArguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/generate_psgc_index.dart [--check]');
    exitCode = 64;
    return;
  }

  final root = File.fromUri(Platform.script).parent.parent;
  final output = File(
    '${root.path}${Platform.pathSeparator}assets'
    '${Platform.pathSeparator}regionJson'
    '${Platform.pathSeparator}psgc_index_v1.bin',
  );
  final metadataOutput = File(
    '${root.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}core'
    '${Platform.pathSeparator}services'
    '${Platform.pathSeparator}psgc_index_metadata.g.dart',
  );
  final artifact = await _buildArtifact(root);
  final metadataSource = _buildMetadataSource(artifact);

  if (arguments.contains('--check')) {
    if (!await output.exists()) {
      stderr.writeln('Missing generated artifact: ${output.path}');
      exitCode = 1;
      return;
    }
    if (!await metadataOutput.exists()) {
      stderr.writeln('Missing generated metadata: ${metadataOutput.path}');
      exitCode = 1;
      return;
    }
    final current = await output.readAsBytes();
    final currentMetadata = await metadataOutput.readAsString();
    if (!_bytesEqual(current, artifact) || currentMetadata != metadataSource) {
      stderr.writeln(
        'PSGC artifact or metadata is stale. Run '
        '`dart run tool/generate_psgc_index.dart`.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('PSGC artifact is current (${artifact.length} bytes).');
    return;
  }

  final artifactCurrent =
      await output.exists() &&
      _bytesEqual(await output.readAsBytes(), artifact);
  final metadataCurrent =
      await metadataOutput.exists() &&
      await metadataOutput.readAsString() == metadataSource;
  if (artifactCurrent && metadataCurrent) {
    stdout.writeln(
      'PSGC artifact and metadata are already current '
      '(${artifact.length} bytes).',
    );
    return;
  }

  if (!artifactCurrent) {
    await output.writeAsBytes(artifact, flush: true);
  }
  if (!metadataCurrent) {
    await metadataOutput.writeAsString(metadataSource, flush: true);
  }
  stdout.writeln(
    'Generated PSGC artifact and metadata (${artifact.length} bytes).',
  );
}

Future<Uint8List> _buildArtifact(Directory root) async {
  final sourceDirectory = Directory(
    '${root.path}${Platform.pathSeparator}assets'
    '${Platform.pathSeparator}regionJson',
  );
  final regions = await _readRecords(sourceDirectory, 'regions.json');
  final provinces = await _readRecords(sourceDirectory, 'provinces.json');
  final cities = await _readRecords(
    sourceDirectory,
    'cities-municipalities.json',
  );
  final barangays = await _readRecords(sourceDirectory, 'barangays.json');

  final strings = _StringTable();
  final records = BytesBuilder(copy: false);

  for (final record in regions) {
    _writeStringId(records, strings.required(record, 'code'));
    _writeStringId(records, strings.required(record, 'name'));
    _writeStringId(records, strings.required(record, 'regionName'));
    _writeStringId(records, strings.required(record, 'islandGroupCode'));
    _writeStringId(records, strings.required(record, 'psgc10DigitCode'));
  }

  for (final record in provinces) {
    _writeStringId(records, strings.required(record, 'code'));
    _writeStringId(records, strings.required(record, 'name'));
    _writeStringId(records, strings.required(record, 'regionCode'));
    _writeStringId(records, strings.required(record, 'islandGroupCode'));
    _writeStringId(records, strings.required(record, 'psgc10DigitCode'));
  }

  for (final record in cities) {
    _writeStringId(records, strings.required(record, 'code'));
    _writeStringId(records, strings.required(record, 'name'));
    _writeStringId(records, strings.required(record, 'oldName'));
    var flags = 0;
    if (_requiredBool(record, 'isCapital')) {
      flags |= 1;
    }
    if (_requiredBool(record, 'isCity')) {
      flags |= 2;
    }
    if (_requiredBool(record, 'isMunicipality')) {
      flags |= 4;
    }
    records.addByte(flags);
    _writeStringId(records, strings.stringOrFalse(record, 'provinceCode'));
    _writeStringId(records, strings.stringOrFalse(record, 'districtCode'));
    _writeStringId(records, strings.required(record, 'regionCode'));
    _writeStringId(records, strings.required(record, 'islandGroupCode'));
    _writeStringId(records, strings.required(record, 'psgc10DigitCode'));
  }

  for (final record in barangays) {
    _writeStringId(records, strings.required(record, 'code'));
    _writeStringId(records, strings.required(record, 'name'));
    _writeStringId(records, strings.required(record, 'oldName'));
    _writeStringId(
      records,
      strings.stringOrFalse(record, 'subMunicipalityCode'),
    );
    _writeStringId(records, strings.stringOrFalse(record, 'cityCode'));
    _writeStringId(records, strings.stringOrFalse(record, 'municipalityCode'));
    _writeStringId(records, strings.stringOrFalse(record, 'districtCode'));
    _writeStringId(records, strings.stringOrFalse(record, 'provinceCode'));
    _writeStringId(records, strings.required(record, 'regionCode'));
    _writeStringId(records, strings.required(record, 'islandGroupCode'));
    _writeStringId(records, strings.required(record, 'psgc10DigitCode'));
  }

  final payload = BytesBuilder(copy: false);
  for (final value in strings.values) {
    final encoded = utf8.encode(value);
    _writeUint32(payload, encoded.length);
    payload.add(encoded);
  }
  payload.add(records.takeBytes());
  final payloadBytes = payload.takeBytes();

  final header = ByteData(_headerLength);
  final headerBytes = header.buffer.asUint8List();
  headerBytes.setRange(0, _magic.length, _magic);
  header.setUint32(8, _formatVersion, Endian.little);
  header.setUint32(12, payloadBytes.length, Endian.little);
  header.setUint64(16, _fnv1a(payloadBytes), Endian.little);
  header.setUint32(24, regions.length, Endian.little);
  header.setUint32(28, provinces.length, Endian.little);
  header.setUint32(32, cities.length, Endian.little);
  header.setUint32(36, barangays.length, Endian.little);
  header.setUint32(40, strings.values.length, Endian.little);

  return Uint8List.fromList(<int>[...headerBytes, ...payloadBytes]);
}

String _buildMetadataSource(Uint8List artifact) {
  final header = ByteData.sublistView(artifact, 0, _headerLength);
  final checksum = header
      .getUint64(16, Endian.little)
      .toRadixString(16)
      .padLeft(16, '0');
  return '''// Generated by tool/generate_psgc_index.dart. Do not edit by hand.

import 'psgc_index_types.dart';

const psgcCanonicalMetadata = PsgcArtifactMetadata(
  formatVersion: ${header.getUint32(8, Endian.little)},
  artifactBytes: ${artifact.length},
  payloadBytes: ${header.getUint32(12, Endian.little)},
  payloadChecksumHex: '$checksum',
  stringCount: ${header.getUint32(40, Endian.little)},
  counts: PsgcCounts(
    regions: ${header.getUint32(24, Endian.little)},
    provinces: ${header.getUint32(28, Endian.little)},
    cities: ${header.getUint32(32, Endian.little)},
    barangays: ${header.getUint32(36, Endian.little)},
  ),
);
''';
}

Future<List<Map<String, dynamic>>> _readRecords(
  Directory directory,
  String fileName,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) {
    throw FormatException('$fileName must contain a JSON array.');
  }
  return decoded
      .map((value) {
        if (value is! Map<String, dynamic>) {
          throw FormatException('$fileName contains a non-object record.');
        }
        return value;
      })
      .toList(growable: false);
}

bool _requiredBool(Map<String, dynamic> record, String key) {
  final value = record[key];
  if (value is! bool) {
    throw FormatException(
      '${record['code'] ?? '<unknown>'}.$key must be a boolean.',
    );
  }
  return value;
}

void _writeStringId(BytesBuilder output, int id) {
  _writeUint32(output, id);
}

void _writeUint32(BytesBuilder output, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  output.add(data.buffer.asUint8List());
}

int _fnv1a(List<int> bytes) {
  var hash = _fnvOffsetBasis;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * _fnvPrime) & _uint64Mask;
  }
  return hash;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

class _StringTable {
  final List<String> values = <String>[];
  final Map<String, int> _ids = <String, int>{};

  int required(Map<String, dynamic> record, String key) {
    final value = record[key];
    if (value is! String) {
      throw FormatException(
        '${record['code'] ?? '<unknown>'}.$key must be a string.',
      );
    }
    return _intern(value);
  }

  int stringOrFalse(Map<String, dynamic> record, String key) {
    final value = record[key];
    if (value == false) {
      return _missingString;
    }
    if (value is! String) {
      throw FormatException(
        '${record['code'] ?? '<unknown>'}.$key must be a string or false.',
      );
    }
    return _intern(value);
  }

  int _intern(String value) {
    final existing = _ids[value];
    if (existing != null) {
      return existing;
    }
    final id = values.length;
    if (id >= _missingString) {
      throw StateError('PSGC string table exceeds the format limit.');
    }
    values.add(value);
    _ids[value] = id;
    return id;
  }
}
