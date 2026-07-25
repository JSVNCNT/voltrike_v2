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
import '../features/ride/calls/voice_call_screen.dart';
import '../data/repositories/booking_voice_call_repository.dart';

import '../features/driver/presentation/screens/driver_settings_screen.dart';
import '../features/passenger/presentation/screens/passenger_shell_screen.dart';
import '../features/passenger/presentation/screens/passenger_dashboard_screen.dart';
import '../features/passenger/presentation/screens/passenger_profile_screen.dart';
import '../features/passenger/presentation/screens/passenger_trip_history_screen.dart';
import '../features/passenger/presentation/screens/searching_driver_screen.dart';
import '../features/passenger/presentation/screens/booking_tracking_screen.dart';
import '../features/passenger/presentation/screens/rating_screen.dart';

import '../features/driver/presentation/screens/driver_shell_screen.dart';
import '../features/driver/presentation/screens/driver_home_screen.dart';
import '../features/driver/presentation/screens/driver_dashboard_screen.dart';
import '../features/driver/presentation/screens/driver_profile_screen.dart';
import '../features/driver/presentation/screens/driver_trip_history_screen.dart';
import '../features/driver/presentation/screens/driver_earnings_screen.dart';
import '../features/driver/presentation/screens/edit_driver_profile_screen.dart';
import '../features/driver/presentation/screens/about_voltrike_screen.dart' as about;
import '../features/driver/presentation/screens/privacy_policy_screen.dart' as privacy;
import '../features/driver/presentation/screens/terms_and_conditions_screen.dart';
import '../features/passenger/presentation/screens/passenger_settings_screen.dart';
import '../features/passenger/presentation/screens/edit_passenger_profile_screen.dart';
import '../features/driver/presentation/screens/driver_booking_tracking_screen.dart';
import '../features/ride/chat/booking_chat_screen.dart';

import 'routes.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,

  errorBuilder: (
    context,
    state,
  ) {
    return Scaffold(
      body: Center(
        child: Text(
          'Route not found:\n${state.uri}',
          textAlign:
              TextAlign.center,
        ),
      ),
    );
  },

  routes: [
        //==========================================================================
    // Startup
    //==========================================================================

    GoRoute(
      path: AppRoutes.splash,
      builder: (
        context,
        state,
      ) =>
          const SplashScreen(),
    ),

    GoRoute(
      path: AppRoutes.intro,
      builder: (
        context,
        state,
      ) =>
          const IntroScreen(),
    ),

    //==========================================================================
    // Authentication
    //==========================================================================

    GoRoute(
      path: AppRoutes.login,
      builder: (
        context,
        state,
      ) =>
          const LoginScreen(),
    ),

    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (
        context,
        state,
      ) =>
          const ForgotPasswordScreen(),
    ),

    GoRoute(
      path: AppRoutes.emailVerification,
      builder: (
        context,
        state,
      ) =>
          const EmailVerificationScreen(),
    ),

    //==========================================================================
    // Passenger Registration
    //==========================================================================

    GoRoute(
      path: AppRoutes.passengerRegister,
      builder: (
        context,
        state,
      ) =>
          const PassengerRegistrationScreen(),
    ),

    GoRoute(
      path: AppRoutes.passengerRegisterSuccess,
      builder: (
        context,
        state,
      ) =>
          const PassengerRegistrationSuccessScreen(),
    ),

    //==========================================================================
    // Driver Registration
    //==========================================================================

    GoRoute(
      path: AppRoutes.driverRegister,
      builder: (
        context,
        state,
      ) =>
          const DriverRegistrationStep1Screen(),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep1,
      builder: (
        context,
        state,
      ) =>
          const DriverRegistrationStep1Screen(),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep2,
      builder: (
        context,
        state,
      ) =>
          const DriverRegistrationStep2Screen(),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep3,
      builder: (
        context,
        state,
      ) =>
          const DriverRegistrationStep3Screen(),
    ),

    GoRoute(
      path: AppRoutes.uploadDocuments,
      builder: (
        context,
        state,
      ) =>
          const UploadDocumentsScreen(),
    ),

    GoRoute(
      path: AppRoutes.driverUnderReview,
      builder: (
        context,
        state,
      ) =>
          const DriverUnderReviewScreen(),
    ),
        //==========================================================================
    // Passenger
    //==========================================================================

    GoRoute(
      path: AppRoutes.passengerHome,
      builder: (
        context,
        state,
      ) =>
          const PassengerShellScreen(),
    ),

    GoRoute(
      path: AppRoutes.passengerDashboard,
      builder: (
        context,
        state,
      ) =>
          const PassengerDashboardScreen(),
    ),

    GoRoute(
      path: AppRoutes.passengerProfile,
      builder: (
        context,
        state,
      ) =>
          const PassengerProfileScreen(),
    ),

    GoRoute(
  path: AppRoutes.editPassengerProfile,
  builder: (
    context,
    state,
  ) =>
      const EditPassengerProfileScreen(),
),

GoRoute(
  path: AppRoutes.passengerSettings,
  builder: (
    context,
    state,
  ) =>
      const PassengerSettingsScreen(),
),

    GoRoute(
      path: AppRoutes.passengerTripHistory,
      builder: (
        context,
        state,
      ) =>
          const PassengerTripHistoryScreen(),
    ),

    //==========================================================================
    // Passenger Booking Flow
    //==========================================================================

    GoRoute(
      path: AppRoutes.searchingDriver,
      builder: (
        context,
        state,
      ) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return SearchingDriverScreen(
          bookingId: bookingId,
        );
      },
    ),

    GoRoute(
      path: AppRoutes.driverTracking,
      builder: (
        context,
        state,
      ) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return BookingTrackingScreen(
          bookingId: bookingId,
        );
      },
    ),

    GoRoute(
      path: AppRoutes.passengerTrip,
      builder: (
        context,
        state,
      ) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return BookingTrackingScreen(
          bookingId: bookingId,
        );
      },
    ),

    GoRoute(
      path: AppRoutes.rateDriver,
      builder: (
        context,
        state,
      ) {
        final bookingId =
            state.extra as String;

        return RatingScreen(
          bookingId: bookingId,
        );
      },
    ),
        //==========================================================================
    // Driver
    //==========================================================================

    GoRoute(
      path: AppRoutes.driverHome,
      builder: (
        context,
        state,
      ) =>
          const DriverShellScreen(),
    ),

    GoRoute(
      path: AppRoutes.driverDashboard,
      builder: (
        context,
        state,
      ) =>
          const DriverDashboardScreen(),
    ),

    GoRoute(
      path: AppRoutes.driverProfile,
      builder: (
        context,
        state,
      ) =>
          const DriverProfileScreen(),
    ),

    GoRoute(
  path: AppRoutes.editDriverProfile,
  builder: (
    context,
    state,
  ) =>
      const EditDriverProfileScreen(),
),

GoRoute(
  path: AppRoutes.aboutVoltrike,
  builder: (
    context,
    state,
  ) =>
      const about.AboutVoltrikeScreen(),
),

GoRoute(
  path: AppRoutes.privacyPolicy,
  builder: (
    context,
    state,
  ) =>
      const privacy.PrivacyPolicyScreen(),
),

GoRoute(
  path: AppRoutes.termsAndConditions,
  builder: (
    context,
    state,
  ) =>
      const TermsAndConditionsScreen(),
),

GoRoute(
  path: AppRoutes.driverSettings,
  builder: (
    context,
    state,
  ) =>
      const DriverSettingsScreen(),
),


    GoRoute(
      path: AppRoutes.driverTripHistory,
      builder: (
        context,
        state,
      ) =>
          const DriverTripHistoryScreen(),
    ),

    GoRoute(
  path: AppRoutes.driverEarnings,
  builder: (context, state) {
    final driverId = state.extra as String;

    return DriverEarningsScreen(
      driverId: driverId,
    );
  },
),

GoRoute(
  path: AppRoutes.driverBookingTracking,
  builder: (
    context,
    state,
  ) =>
      DriverBookingTrackingScreen(
        bookingId: state.extra as String?,
      ),
),

    GoRoute(
      path: AppRoutes.currentBooking,
  builder: (
    context,
    state,
  ) =>
      const DriverHomeScreen(),
    ),

    GoRoute(
      path: AppRoutes.bookingChat,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final bookingId = extra?['bookingId'] as String?;
        final members = (extra?['members'] as List?)?.cast<String>();
        if (bookingId == null || members == null) return const PassengerShellScreen();
        return BookingChatScreen(bookingId: bookingId, members: members);
      },
    ),

    GoRoute(
      path: AppRoutes.bookingVoiceCall,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }
        return VoiceCallScreen(
          connect: (service) async {
            final credentials =
                await BookingVoiceCallRepository().createCredentials(bookingId);
            await service.connect(
              serverUrl: credentials.serverUrl,
              token: credentials.token,
            );
          },
          endCall: () => BookingVoiceCallRepository().endCall(bookingId),
        );
      },
    ),

],
);
