import 'package:flutter/material.dart';

import '../../../common/presentation/screens/app_shell_screen.dart';
import '../../../common/presentation/widgets/app_navigation_destination.dart';

import 'driver_dashboard_screen.dart';
import 'driver_home_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_trip_history_screen.dart';

/// ===========================================================================
/// Driver Shell
///
/// Entry point after a driver logs in.
///
/// Provides the pages shown in the shared AppShell.
/// ===========================================================================
class DriverShellScreen extends StatelessWidget {
  const DriverShellScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppShellScreen(
      destinations: const [
        AppNavigationDestination(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          page: DriverHomeScreen(),
        ),
        AppNavigationDestination(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          page: DriverDashboardScreen(),
        ),
        AppNavigationDestination(
          label: 'Trips',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          page: DriverTripHistoryScreen(),
        ),
        AppNavigationDestination(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          page: DriverProfileScreen(),
        ),
      ],
    );
  }
}