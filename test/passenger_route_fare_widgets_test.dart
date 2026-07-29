import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/fare_card.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/home_bottom_sheet.dart';

void main() {
  Widget app(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('same-zone fare hides the Outside TODA surcharge row', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const FareCard(estimatedFare: '₱45.00', boundarySurcharge: '₱20.00')),
    );

    expect(find.text('Outside TODA surcharge'), findsNothing);
    expect(find.text('₱20.00'), findsNothing);
  });

  testWidgets('outside trip highlights the exact configured surcharge', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const FareCard(
          estimatedFare: '₱65.00',
          boundarySurcharge: '₱20.00',
          isOutsideToda: true,
        ),
      ),
    );

    expect(find.text('Outside TODA surcharge'), findsOneWidget);
    expect(find.text('₱20.00'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('safe alternative advisory remains visible in ride summary', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const advisory =
        'Route adjusted to avoid Circumferential Road. Follow the route shown '
        'on the map.';

    await tester.pumpWidget(
      app(
        HomeBottomSheet(
          scrollController: controller,
          pickup: 'Barangay 40',
          destination: 'Bacolod City Hall',
          hasRoute: true,
          routeAdvisory: advisory,
        ),
      ),
    );

    expect(find.text('Route advisory'), findsOneWidget);
    expect(find.text(advisory), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
