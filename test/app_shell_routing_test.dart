import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/common/presentation/screens/app_shell_screen.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/app_navigation_destination.dart';

void main() {
  const destinations = [
    AppNavigationDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      page: Text('home-page'),
    ),
    AppNavigationDestination(
      label: 'Trips',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      page: Text('trips-page'),
    ),
  ];

  testWidgets('coordinator can consume home tab selection', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: AppShellScreen(
          destinations: destinations,
          initialIndex: 1,
          onDestinationSelected: (index) {
            selectedIndex = index;
            return index == 0;
          },
        ),
      ),
    );

    expect(find.text('trips-page'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pump();

    expect(selectedIndex, 0);
    expect(find.text('trips-page'), findsOneWidget);
    expect(find.text('home-page'), findsNothing);
  });

  testWidgets('unhandled tab selection updates the shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShellScreen(
          destinations: destinations,
          onDestinationSelected: (_) => false,
        ),
      ),
    );

    await tester.tap(find.text('Trips'));
    await tester.pump();

    expect(find.text('trips-page'), findsOneWidget);
    expect(find.text('home-page'), findsNothing);
  });
}
