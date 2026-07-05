import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/splash/presentations/screens/splash_screen.dart';
import 'routes.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,

  debugLogDiagnostics: true,

  routes: [

    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) =>
          const SplashScreen(),
    ),

  ],
);