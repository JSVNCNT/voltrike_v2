import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/presentation/screens/app_shell_screen.dart';
import '../../../common/presentation/widgets/app_navigation_destination.dart';
import '../../../ride/routing/booking_route_coordinator.dart';
import '../../../ride/routing/booking_route_resolver.dart';
import '../../providers/active_booking_provider.dart';

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
class PassengerShellScreen extends ConsumerWidget {
  const PassengerShellScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBooking = ref.watch(activePassengerBookingProvider).value;

    return BookingRouteCoordinator(
      role: BookingParticipantRole.passenger,
      booking: activeBooking,
      redirectActiveBooking: initialIndex == 0,
      child: AppShellScreen(
        initialIndex: initialIndex,
        onDestinationSelected: (index) {
          if (index != 0 || activeBooking == null) return false;
          BookingRouteCoordinator.open(
            context,
            role: BookingParticipantRole.passenger,
            booking: activeBooking,
          );
          return true;
        },
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
      ),
    );
  }
}
