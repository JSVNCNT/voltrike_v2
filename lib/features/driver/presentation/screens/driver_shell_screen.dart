import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/presentation/screens/app_shell_screen.dart';
import '../../../common/presentation/widgets/app_navigation_destination.dart';
import '../../../ride/routing/booking_route_coordinator.dart';
import '../../../ride/routing/booking_route_resolver.dart';
import '../../providers/driver_booking_provider.dart';
import '../../providers/driver_current_booking_provider.dart';

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
class DriverShellScreen extends ConsumerStatefulWidget {
  const DriverShellScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<DriverShellScreen> createState() => _DriverShellScreenState();
}

class _DriverShellScreenState extends ConsumerState<DriverShellScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(driverBookingControllerProvider.notifier)
          .restoreCurrentBooking(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeBooking = ref.watch(driverCurrentBookingProvider);

    return BookingRouteCoordinator(
      role: BookingParticipantRole.driver,
      booking: activeBooking,
      redirectActiveBooking: widget.initialIndex == 0,
      child: AppShellScreen(
        initialIndex: widget.initialIndex,
        onDestinationSelected: (index) {
          if (index != 0 || activeBooking == null) return false;
          BookingRouteCoordinator.open(
            context,
            role: BookingParticipantRole.driver,
            booking: activeBooking,
          );
          return true;
        },
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
      ),
    );
  }
}
