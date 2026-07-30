import 'psgc_index_bridge_contract.dart';
import 'psgc_index_bridge_stub.dart'
    if (dart.library.io) 'psgc_index_bridge_io.dart'
    as implementation;

export 'psgc_index_bridge_contract.dart';

PsgcIndexBridge createPsgcIndexBridge() =>
    implementation.createPsgcIndexBridge();
