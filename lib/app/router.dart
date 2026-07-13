import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/screens/email_verification/email_verification_screen.dart';
import '../features/auth/presentation/screens/forgot_password/forgot_password_screen.dart';
import '../features/auth/presentation/screens/intro/intro_screen.dart';
import '../features/auth/presentation/screens/login/login_screen.dart';

import '../features/auth/presentation/screens/passenger_registration/passenger_registration_screen.dart';
import '../features/auth/presentation/screens/passenger_registration/passenger_registration_success_screen.dart';

import '../features/auth/presentation/screens/driver_registration/driver_registration_step1_screen.dart';
import '../features/auth/presentation/screens/driver_registration/driver_registration_step2_screen.dart';
import '../features/auth/presentation/screens/driver_registration/driver_registration_step3_screen.dart';
import '../features/auth/presentation/screens/driver_registration/upload_documents_screen.dart';
import '../features/auth/presentation/screens/driver_registration/under_review_screen.dart';

import '../features/auth/presentation/screens/splash/splash_screen.dart';

import 'routes.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,

  debugLogDiagnostics: true,

  errorBuilder: (context, state) {
    return Scaffold(
      body: Center(
        child: Text(
          'Route not found:\n${state.uri}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  },

  routes: [
    // =========================================================================
    // Startup
    // =========================================================================

    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) =>
          const SplashScreen(),
    ),

    GoRoute(
      path: AppRoutes.intro,
      builder: (context, state) =>
          const IntroScreen(),
    ),

    // =========================================================================
    // Authentication
    // =========================================================================

    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) =>
          const LoginScreen(),
    ),

    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (context, state) =>
          const ForgotPasswordScreen(),
    ),

    GoRoute(
      path: AppRoutes.emailVerification,
      builder: (context, state) =>
          const EmailVerificationScreen(),
    ),

    // =========================================================================
    // Passenger Registration
    // =========================================================================

    GoRoute(
      path: AppRoutes.passengerRegister,
      builder: (context, state) =>
          const PassengerRegistrationScreen(),
    ),

    GoRoute(
      path: AppRoutes.passengerRegisterSuccess,
      builder: (context, state) =>
          const PassengerRegistrationSuccessScreen(),
    ),

// =========================================================================
// Driver Registration
// =========================================================================

GoRoute(
  path: AppRoutes.driverRegister,
  builder: (context, state) =>
      const DriverRegistrationStep1Screen(),
),

GoRoute(
  path: AppRoutes.driverRegisterStep1,
  builder: (context, state) =>
      const DriverRegistrationStep1Screen(),
),

GoRoute(
  path: AppRoutes.driverRegisterStep2,
  builder: (context, state) =>
      const DriverRegistrationStep2Screen(),
),

GoRoute(
  path: AppRoutes.driverRegisterStep3,
  builder: (context, state) =>
      const DriverRegistrationStep3Screen(),
),

GoRoute(
  path: AppRoutes.uploadDocuments,
  builder: (context, state) =>
      const UploadDocumentsScreen(),
),

GoRoute(
  path: AppRoutes.driverUnderReview,
  builder: (context, state) =>
      const DriverUnderReviewScreen(),
),

  ],
);