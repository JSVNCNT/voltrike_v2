import 'package:flutter/material.dart';

import '../../../common/presentation/screens/app_shell_screen.dart';
import '../../../common/presentation/widgets/app_navigation_destination.dart';

import 'passenger_dashboard_screen.dart';
import 'passenger_home_screen.dart';
import 'passenger_profile_screen.dart';
import 'passenger_trip_history_screen.dart';

/// ===========================================================================
/// Passenger Shell
///
/// Entry point after a passenger logs in.
///
/// Provides the pages shown in the shared AppShell.
/// ===========================================================================
class PassengerShellScreen extends StatelessWidget {
  const PassengerShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShellScreen(
      destinations: const [
        AppNavigationDestination(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          page: PassengerHomeScreen(),
        ),
        AppNavigationDestination(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          page: PassengerDashboardScreen(),
        ),
        AppNavigationDestination(
          label: 'Trips',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          page: PassengerTripHistoryScreen(),
        ),
        AppNavigationDestination(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          page: PassengerProfileScreen(),
        ),
      ],
    );
  }
}