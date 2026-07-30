import 'rust_navigation_bridge_contract.dart';
import 'rust_navigation_bridge_stub.dart'
    if (dart.library.io) 'rust_navigation_bridge_io.dart'
    as implementation;

export 'rust_navigation_bridge_contract.dart';

RustNavigationBridge createRustNavigationBridge() =>
    implementation.createRustNavigationBridge();
