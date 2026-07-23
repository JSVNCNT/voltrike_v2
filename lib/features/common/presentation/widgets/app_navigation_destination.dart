import 'package:flutter/material.dart';

/// ===========================================================================
/// App Navigation Destination
///
/// Model used by the shared application shell.
///
/// Passenger and Driver each provide a list of
/// AppNavigationDestination objects to build
/// the BottomNavigationBar and corresponding pages.
///
/// Example:
///
/// Passenger
/// - Home
/// - Dashboard
/// - Trips
/// - Profile
///
/// Driver
/// - Home
/// - Dashboard
/// - Earnings
/// - Profile
/// ===========================================================================
@immutable
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  /// Label shown below the icon.
  final String label;

  /// Default icon.
  final IconData icon;

  /// Selected icon.
  final IconData selectedIcon;

  /// Screen displayed when selected.
  final Widget page;
}