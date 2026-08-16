import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/theme/app_semantic_colors.dart';
import 'package:voltrike_v2/core/theme/app_theme.dart';
import 'package:voltrike_v2/core/widgets/cards/app_card.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/dashboard_widgets.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/app_app_bar.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/app_bottom_navigation.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/app_navigation_destination.dart';
import 'package:voltrike_v2/features/common/presentation/widgets/profile_widgets.dart';
import 'package:voltrike_v2/features/driver/controllers/driver_earnings_controller.dart';
import 'package:voltrike_v2/features/driver/presentation/screens/driver_earnings_screen.dart';
import 'package:voltrike_v2/features/passenger/presentation/widgets/location_search_bar.dart';

void main() {
  testWidgets('accent card remains interactive in dark mode', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: AppCard(
            accentColor: AppSemanticColors.dark.success,
            accentEdge: AppCardAccentEdge.leading,
            tintColor: AppSemanticColors.dark.success,
            onTap: () => tapped = true,
            child: const Text('Open card'),
          ),
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, isNot(AppTheme.darkTheme.cardTheme.color));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.ignoring,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Open card'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared dashboard and profile rows fit a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: Column(
              children: [
                DashboardIdentityCard(
                  eyebrow: 'Driver dashboard',
                  name: 'A long driver account name',
                  statusLabel: 'Online',
                ),
                SizedBox(height: 16),
                DashboardMetricGrid(
                  children: [
                    DashboardMetricCard(
                      icon: Icons.route_outlined,
                      value: '1,234',
                      label: 'All trips',
                    ),
                    DashboardMetricCard(
                      icon: Icons.check_circle_outline,
                      value: '987',
                      label: 'Completed',
                    ),
                  ],
                ),
                SizedBox(height: 16),
                ProfileSection(
                  title: 'Driver information',
                  children: [
                    ProfileInfoTile(
                      icon: Icons.badge_outlined,
                      label: 'Vehicle ID',
                      value: 'b877c610-1266-4a20-80b1-593b3f5454aa',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Driver information'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation has a visible top accent in dark mode', (
    tester,
  ) async {
    var selected = -1;
    const destinations = [
      AppNavigationDestination(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        page: SizedBox(),
      ),
      AppNavigationDestination(
        label: 'Profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        page: SizedBox(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigation(
            destinations: destinations,
            currentIndex: 0,
            onDestinationSelected: (index) => selected = index,
          ),
        ),
      ),
    );

    final frame = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-bottom-navigation-frame')),
    );
    final decoration = frame.decoration as BoxDecoration;
    expect(frame.position, DecorationPosition.foreground);
    expect(decoration.border!.top.width, 1.5);
    expect(
      decoration.border!.top.color,
      AppTheme.darkTheme.colorScheme.onSurface.withValues(alpha: 0.6),
    );

    await tester.tap(find.text('Profile'));
    expect(selected, 1);
  });

  testWidgets('earnings view keeps today and separates completed gross', (
    tester,
  ) async {
    const summary = DriverEarningsSummary(
      today: 125,
      week: 500,
      month: 900,
      total: 850,
      completedTripAmount: 1000,
      completedTrips: 12,
      averageFare: 70.83,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: DriverEarningsSummaryView(data: summary)),
      ),
    );

    expect(find.text("Today's earnings"), findsOneWidget);
    expect(find.text('₱125.00'), findsOneWidget);
    expect(find.text('Completed-trip amount'), findsOneWidget);
    expect(find.text('₱1000.00'), findsOneWidget);
    expect(find.text('Total net earnings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary tab app bar keeps its title left aligned', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(appBar: AppAppBar(title: 'Profile')),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final appBarBorder = appBar.shape as Border;
    expect(appBar.centerTitle, isFalse);
    expect(appBarBorder.bottom.width, 1.5);
    expect(appBarBorder.bottom.color, AppTheme.lightTheme.colorScheme.outline);
  });

  testWidgets('profile identity content is centered in the full card width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ProfileIdentityHeader(
              name: 'Centered driver',
              subtitle: 'driver@example.com',
              statusLabel: 'Online',
            ),
          ),
        ),
      ),
    );

    final cardCenter = tester.getCenter(find.byType(Card));
    final nameCenter = tester.getCenter(find.text('Centered driver'));
    final statusCenter = tester.getCenter(find.text('Online'));
    expect((nameCenter.dx - cardCenter.dx).abs(), lessThan(1));
    expect((statusCenter.dx - cardCenter.dx).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile identity exposes an accessible photo edit action', (
    tester,
  ) async {
    var editPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ProfileIdentityHeader(
            name: 'Passenger Test',
            subtitle: 'passenger@example.com',
            onEditPhoto: () => editPressed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Edit profile photo'));
    expect(editPressed, isTrue);
  });

  testWidgets('location search bars use neutral grey theme surfaces', (
    tester,
  ) async {
    Future<Color?> fieldColor(ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          themeAnimationDuration: Duration.zero,
          home: const Scaffold(
            body: LocationSearchBar(hintText: 'Select pickup'),
          ),
        ),
      );
      await tester.pump();
      final ink = tester.widget<Ink>(find.byType(Ink));
      return (ink.decoration as BoxDecoration).color;
    }

    expect(await fieldColor(ThemeMode.light), const Color(0xFFE8ECEC));
    expect(await fieldColor(ThemeMode.dark), const Color(0xFF293536));
  });
}
