import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/restricted_area_legend.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/fare_card.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/home_bottom_sheet.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/ride_type_selector.dart';
import 'package:voltrike_v2/data/models/ride_type.dart';

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
          isExpanded: false,
          onToggleExpanded: () {},
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

  testWidgets('book ride sheet exposes an accessible expand control', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var toggled = false;

    await tester.pumpWidget(
      app(
        HomeBottomSheet(
          scrollController: controller,
          isExpanded: false,
          onToggleExpanded: () => toggled = true,
          pickup: 'Current location',
          destination: 'Where are you going?',
        ),
      ),
    );

    expect(find.byTooltip('Show booking form'), findsOneWidget);
    await tester.tap(find.byTooltip('Show booking form'));
    expect(toggled, isTrue);
  });

  testWidgets('restricted-area legend remains visible in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(body: RestrictedAreaLegend()),
      ),
    );

    expect(find.text('Restricted area'), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
  });

  testWidgets('ride selector shows both assets and locks E-Trike at 3 riders', (
    tester,
  ) async {
    RideType? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RideTypeSelector(
            selectedType: RideType.eTuktuk,
            passengerCount: 3,
            eTrikeFare: '₱45.00',
            eTuktukFare: '₱55.00',
            eTrikeEnabled: true,
            eTuktukEnabled: true,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('E-Trike'), findsOneWidget);
    expect(find.text('E-Tuktuk'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.textContaining('maximum capacity of 2'), findsOneWidget);
    await tester.tap(find.text('E-Trike'));
    expect(selected, isNull);
  });
}
