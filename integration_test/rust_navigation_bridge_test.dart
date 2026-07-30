import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voltrike_v2/core/native/rust_navigation_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('executes the cached navigation bridge on Android', (
    tester,
  ) async {
    final bridge = createRustNavigationBridge();
    expect(bridge.isSupported, isTrue);

    const encodedRoute = 'o~b`AotlmV?gEgEgE';
    final install = await bridge.installRoute(encodedRoute);
    expect(install.pointCount, 3);
    expect(install.segmentCount, 2);
    expect(install.totalDistanceMeters, greaterThan(150));

    final batch = await bridge.processSamples(
      samples: const [
        ActiveRouteGpsSample(
          latitude: 10.67,
          longitude: 122.9505,
          accuracyMeters: 5,
          timestampMillis: 1000,
        ),
      ],
      expectedRouteGeneration: install.routeGeneration,
    );
    expect(batch.acceptedCount, 1);
    expect(batch.rejectedCount, 0);
    expect(batch.samples.single.isAccepted, isTrue);
    expect(batch.samples.single.remainingDistanceMeters, greaterThan(0));

    final cleared = await bridge.clearRoute(install.routeGeneration);
    expect(cleared.routeGeneration, install.routeGeneration);
  });
}
