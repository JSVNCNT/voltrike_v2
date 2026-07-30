import 'registration_image_bridge_contract.dart';
import 'registration_image_bridge_stub.dart'
    if (dart.library.io) 'registration_image_bridge_io.dart'
    as implementation;

export 'registration_image_bridge_contract.dart';

NativeRegistrationImageBridge createNativeRegistrationImageBridge() =>
    implementation.createNativeRegistrationImageBridge();
