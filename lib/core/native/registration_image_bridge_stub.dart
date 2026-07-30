import 'registration_image_bridge_contract.dart';

NativeRegistrationImageBridge createNativeRegistrationImageBridge() =>
    const UnsupportedNativeRegistrationImageBridge();

class UnsupportedNativeRegistrationImageBridge
    implements NativeRegistrationImageBridge {
  const UnsupportedNativeRegistrationImageBridge();

  @override
  bool get isSupported => false;

  @override
  Future<NativeRegistrationImageResult> prepare(
    NativeRegistrationImageRequest request,
  ) {
    return Future<NativeRegistrationImageResult>.error(
      UnsupportedError(
        'The VolTrike Rust image bridge is supported on Android only.',
      ),
    );
  }
}
