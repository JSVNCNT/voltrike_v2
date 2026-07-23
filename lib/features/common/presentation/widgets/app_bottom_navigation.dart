import 'package:flutter/material.dart';

import 'app_navigation_destination.dart';

/// ===========================================================================
/// App Bottom Navigation
///
/// Shared bottom navigation for the mobile application.
///
/// Used by:
/// • Passenger Shell
/// • Driver Shell
///
/// The destinations are provided by the parent shell.
/// ===========================================================================
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final List<AppNavigationDestination> destinations;

  final int currentIndex;

  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations
          .map(
            (destination) => NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(
                destination.selectedIcon,
              ),
              label: destination.label,
            ),
          )
          .toList(),
    );
  }
}