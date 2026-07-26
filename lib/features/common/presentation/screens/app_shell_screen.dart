import 'package:flutter/material.dart';

import '../widgets/app_bottom_navigation.dart';
import '../widgets/app_navigation_destination.dart';

/// ===========================================================================
/// App Shell Screen
///
/// Shared shell used by:
///
/// • Passenger
/// • Driver
///
/// Keeps each tab alive using IndexedStack.
/// ===========================================================================
class AppShellScreen extends StatefulWidget {
  const AppShellScreen({
    super.key,
    required this.destinations,
    this.initialIndex = 0,
    this.onDestinationSelected,
  });

  final List<AppNavigationDestination> destinations;

  final int initialIndex;

  /// Returns true when the destination was handled by an external coordinator.
  final bool Function(int index)? onDestinationSelected;

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant AppShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _currentIndex = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: widget.destinations
            .map((destination) => destination.page)
            .toList(),
      ),

      bottomNavigationBar: AppBottomNavigation(
        destinations: widget.destinations,
        currentIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (widget.onDestinationSelected?.call(index) == true) {
            return;
          }
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
