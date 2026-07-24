import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/navigation_service.dart';

import '../controllers/driver_navigation_controller.dart';

/// ===========================================================================
/// Navigation Service Provider
/// ===========================================================================
final driverNavigationServiceProvider =
    Provider<NavigationService>(
  (ref) => NavigationService.instance,
);

/// ===========================================================================
/// Driver Navigation Controller Provider
/// ===========================================================================
final driverNavigationControllerProvider =
    StateNotifierProvider<
        DriverNavigationController,
        DriverNavigationState>(
  (ref) {
    return DriverNavigationController(
      navigationService: ref.read(
        driverNavigationServiceProvider,
      ),
    );
  },
);