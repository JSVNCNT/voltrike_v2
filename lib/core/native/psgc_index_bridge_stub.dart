import 'dart:typed_data';

import '../services/psgc_index_types.dart';
import 'psgc_index_bridge_contract.dart';

PsgcIndexBridge createPsgcIndexBridge() => const UnsupportedPsgcIndexBridge();

class UnsupportedPsgcIndexBridge implements PsgcIndexBridge {
  const UnsupportedPsgcIndexBridge();

  @override
  bool get isSupported => false;

  @override
  Future<PsgcArtifactMetadata> initialize(Uint8List artifact) {
    throw UnsupportedError(
      'The VolTrike Rust PSGC bridge is not available in this build.',
    );
  }

  @override
  List<PsgcEntry> entries(PsgcLevel level, {String? parentCode}) {
    throw UnsupportedError(
      'The VolTrike Rust PSGC bridge is not available in this build.',
    );
  }

  @override
  PsgcEntry? findByName(PsgcLevel level, String name, {String? parentCode}) {
    throw UnsupportedError(
      'The VolTrike Rust PSGC bridge is not available in this build.',
    );
  }

  @override
  String? nameForCode(PsgcLevel level, String code) {
    throw UnsupportedError(
      'The VolTrike Rust PSGC bridge is not available in this build.',
    );
  }
}
