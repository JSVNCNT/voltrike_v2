import 'rust_geometry_bridge_contract.dart';
import 'rust_geometry_bridge_stub.dart'
    if (dart.library.io) 'rust_geometry_bridge_io.dart'
    as implementation;

export 'rust_geometry_bridge_contract.dart';

RustGeometryBridge createRustGeometryBridge() =>
    implementation.createRustGeometryBridge();
