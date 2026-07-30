import 'dart:typed_data';

import '../services/psgc_index_types.dart';

abstract interface class PsgcIndexBridge {
  bool get isSupported;

  Future<PsgcArtifactMetadata> initialize(Uint8List artifact);

  List<PsgcEntry> entries(PsgcLevel level, {String? parentCode});

  PsgcEntry? findByName(PsgcLevel level, String name, {String? parentCode});

  String? nameForCode(PsgcLevel level, String code);
}
