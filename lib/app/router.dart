import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/fixed_light_theme.dart';
import '../features/auth/presentation/screens/email_verification/email_verification_screen.dart';
import '../features/auth/presentation/screens/forgot_password/forgot_password_screen.dart';
import '../features/auth/presentation/screens/intro/intro_screen.dart';
import '../features/auth/presentation/screens/login/login_screen.dart';

import '../features/auth/presentation/screens/passenger_registration/passenger_registration_screen.dart';
import '../features/auth/presentation/screens/passenger_registration/passenger_registration_success_screen.dart';

import '../features/auth/presentation/screens/driver_registration/driver_registration_step1_screen.dart';
import '../features/auth/presentation/screens/driver_registration/driver_registration_step2_screen.dart';
import '../features/auth/presentation/screens/driver_registration/driver_registration_step3_screen.dart';
import '../features/auth/presentation/screens/driver_registration/driver_registration_review_screen.dart';
import '../features/auth/presentation/screens/driver_registration/upload_documents_screen.dart';
import '../features/auth/presentation/screens/driver_registration/under_review_screen.dart';

import '../features/auth/presentation/screens/splash/splash_screen.dart';
import '../features/auth/presentation/widgets/account_status_gate.dart';
import '../features/ride/calls/voice_call_screen.dart';
import '../features/ride/calls/incoming_call_screen.dart';

import '../features/driver/presentation/screens/driver_settings_screen.dart';
import '../features/passenger/presentation/screens/passenger_shell_screen.dart';
import '../features/passenger/presentation/screens/searching_driver_screen.dart';
import '../features/passenger/presentation/screens/booking_tracking_screen.dart';
import '../features/passenger/presentation/screens/rating_screen.dart';
import '../features/passenger/presentation/screens/trip_receipt_screen.dart';

import '../features/driver/presentation/screens/driver_shell_screen.dart';
import '../features/driver/presentation/screens/driver_home_screen.dart';
import '../features/driver/presentation/screens/driver_earnings_screen.dart';
import '../features/driver/presentation/screens/edit_driver_profile_screen.dart';
import '../features/common/presentation/screens/about/about_voltrike_screen.dart'
    as about;
import '../features/common/presentation/screens/legal/privacy_policy_screen.dart'
    as privacy;
import '../features/common/presentation/screens/legal/terms_and_conditions_screen.dart';
import '../features/passenger/presentation/screens/passenger_settings_screen.dart';
import '../features/passenger/presentation/screens/edit_passenger_profile_screen.dart';
import '../features/driver/presentation/screens/driver_booking_tracking_screen.dart';
import '../features/ride/chat/booking_chat_screen.dart';

import 'routes.dart';

Widget _passengerGate(Widget child) {
  return AccountStatusGate(driverAccount: false, child: child);
}

Widget _driverGate(Widget child) {
  return AccountStatusGate(driverAccount: true, child: child);
}

Widget _publicLight(Widget child) {
  return FixedLightTheme(child: child);
}

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
    //==========================================================================
    // Startup
    //==========================================================================
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => _publicLight(const SplashScreen()),
    ),

    GoRoute(
      path: AppRoutes.intro,
      builder: (context, state) => _publicLight(const IntroScreen()),
    ),

    //==========================================================================
    // Authentication
    //==========================================================================
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => _publicLight(const LoginScreen()),
    ),

    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (context, state) => _publicLight(const ForgotPasswordScreen()),
    ),

    GoRoute(
      path: AppRoutes.emailVerification,
      builder: (context, state) =>
          _publicLight(const EmailVerificationScreen()),
    ),

    GoRoute(
      path: AppRoutes.accountSuspended,
      builder: (context, state) => _publicLight(
        const AccountStatusGate(child: _AccountRestoredRedirect()),
      ),
    ),

    //==========================================================================
    // Passenger Registration
    //==========================================================================
    GoRoute(
      path: AppRoutes.passengerRegister,
      builder: (context, state) =>
          _publicLight(const PassengerRegistrationScreen()),
    ),

    GoRoute(
      path: AppRoutes.passengerRegisterSuccess,
      builder: (context, state) =>
          _publicLight(const PassengerRegistrationSuccessScreen()),
    ),

    //==========================================================================
    // Driver Registration
    //==========================================================================
    GoRoute(
      path: AppRoutes.driverRegister,
      builder: (context, state) =>
          _publicLight(const DriverRegistrationStep1Screen()),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep1,
      builder: (context, state) => _publicLight(
        DriverRegistrationStep1Screen(
          returnToReview: state.uri.queryParameters['returnToReview'] == 'true',
        ),
      ),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep2,
      builder: (context, state) => _publicLight(
        DriverRegistrationStep2Screen(
          returnToReview: state.uri.queryParameters['returnToReview'] == 'true',
        ),
      ),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterStep3,
      builder: (context, state) => _publicLight(
        DriverRegistrationStep3Screen(
          returnToReview: state.uri.queryParameters['returnToReview'] == 'true',
        ),
      ),
    ),

    GoRoute(
      path: AppRoutes.uploadDocuments,
      builder: (context, state) => _publicLight(
        UploadDocumentsScreen(
          returnToReview: state.uri.queryParameters['returnToReview'] == 'true',
        ),
      ),
    ),

    GoRoute(
      path: AppRoutes.driverRegisterReview,
      builder: (context, state) =>
          _publicLight(const DriverRegistrationReviewScreen()),
    ),

    GoRoute(
      path: AppRoutes.driverUnderReview,
      builder: (context, state) =>
          _publicLight(const DriverUnderReviewScreen()),
    ),

    //==========================================================================
    // Passenger
    //==========================================================================
    GoRoute(
      path: AppRoutes.passengerHome,
      builder: (context, state) => _passengerGate(const PassengerShellScreen()),
    ),

    GoRoute(
      path: AppRoutes.passengerDashboard,
      builder: (context, state) =>
          _passengerGate(const PassengerShellScreen(initialIndex: 1)),
    ),

    GoRoute(
      path: AppRoutes.passengerProfile,
      builder: (context, state) =>
          _passengerGate(const PassengerShellScreen(initialIndex: 3)),
    ),

    GoRoute(
      path: AppRoutes.editPassengerProfile,
      builder: (context, state) =>
          _passengerGate(const EditPassengerProfileScreen()),
    ),

    GoRoute(
      path: AppRoutes.passengerSettings,
      builder: (context, state) =>
          _passengerGate(const PassengerSettingsScreen()),
    ),

    GoRoute(
      path: AppRoutes.passengerTripHistory,
      builder: (context, state) =>
          _passengerGate(const PassengerShellScreen(initialIndex: 2)),
    ),

    //==========================================================================
    // Passenger Booking Flow
    //==========================================================================
    GoRoute(
      path: AppRoutes.searchingDriver,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return _passengerGate(SearchingDriverScreen(bookingId: bookingId));
      },
    ),

    GoRoute(
      path: AppRoutes.driverTracking,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return _passengerGate(BookingTrackingScreen(bookingId: bookingId));
      },
    ),

    GoRoute(
      path: AppRoutes.passengerTrip,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return _passengerGate(BookingTrackingScreen(bookingId: bookingId));
      },
    ),

    GoRoute(
      path: AppRoutes.rateDriver,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }

        return _passengerGate(RatingScreen(bookingId: bookingId));
      },
    ),

    GoRoute(
      path: AppRoutes.passengerReceipt,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }
        return _passengerGate(
          TripReceiptScreen(bookingId: bookingId, completionFlow: true),
        );
      },
    ),

    //==========================================================================
    // Driver
    //==========================================================================
    GoRoute(
      path: AppRoutes.driverHome,
      builder: (context, state) => _driverGate(const DriverShellScreen()),
    ),

    GoRoute(
      path: AppRoutes.driverDashboard,
      builder: (context, state) =>
          _driverGate(const DriverShellScreen(initialIndex: 1)),
    ),

    GoRoute(
      path: AppRoutes.driverProfile,
      builder: (context, state) =>
          _driverGate(const DriverShellScreen(initialIndex: 3)),
    ),

    GoRoute(
      path: AppRoutes.editDriverProfile,
      builder: (context, state) => _driverGate(const EditDriverProfileScreen()),
    ),

    GoRoute(
      path: AppRoutes.aboutVoltrike,
      builder: (context, state) => const about.AboutVoltrikeScreen(),
    ),

    GoRoute(
      path: AppRoutes.privacyPolicy,
      builder: (context, state) {
        final acknowledgementRequired =
            state.uri.queryParameters['acknowledge'] == 'true';
        final screen = privacy.PrivacyPolicyScreen(
          acknowledgementRequired: acknowledgementRequired,
        );
        return acknowledgementRequired ? _publicLight(screen) : screen;
      },
    ),

    GoRoute(
      path: AppRoutes.termsAndConditions,
      builder: (context, state) {
        final acknowledgementRequired =
            state.uri.queryParameters['acknowledge'] == 'true';
        final screen = TermsAndConditionsScreen(
          acknowledgementRequired: acknowledgementRequired,
        );
        return acknowledgementRequired ? _publicLight(screen) : screen;
      },
    ),

    GoRoute(
      path: AppRoutes.driverSettings,
      builder: (context, state) => _driverGate(const DriverSettingsScreen()),
    ),

    GoRoute(
      path: AppRoutes.driverTripHistory,
      builder: (context, state) =>
          _driverGate(const DriverShellScreen(initialIndex: 2)),
    ),

    GoRoute(
      path: AppRoutes.driverEarnings,
      builder: (context, state) {
        final driverId = state.extra as String;

        return DriverEarningsScreen(driverId: driverId);
      },
    ),

    GoRoute(
      path: AppRoutes.driverBookingTracking,
      builder: (context, state) => _driverGate(
        DriverBookingTrackingScreen(bookingId: state.extra as String?),
      ),
    ),

    GoRoute(
      path: AppRoutes.driverReceipt,
      builder: (context, state) {
        final bookingId = state.extra as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const DriverShellScreen();
        }
        return _driverGate(
          TripReceiptScreen(bookingId: bookingId, driverView: true),
        );
      },
    ),

    GoRoute(
      path: AppRoutes.currentBooking,
      builder: (context, state) => _driverGate(const DriverHomeScreen()),
    ),

    GoRoute(
      path: AppRoutes.bookingChat,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final bookingId = extra?['bookingId'] as String?;
        final members = (extra?['members'] as List?)?.cast<String>();
        if (bookingId == null || members == null) {
          return const PassengerShellScreen();
        }
        return BookingChatScreen(bookingId: bookingId, members: members);
      },
    ),

    GoRoute(
      path: AppRoutes.bookingVoiceCall,
      builder: (context, state) {
        final extra = state.extra;
        final details = extra is Map<String, dynamic> ? extra : null;
        final bookingId = extra is String
            ? extra
            : details?['bookingId'] as String?;
        final callId = details?['callId'] as String?;
        final outgoing = extra is String || details?['outgoing'] != false;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }
        return VoiceCallScreen(
          bookingId: bookingId,
          callId: callId,
          outgoing: outgoing,
        );
      },
    ),

    GoRoute(
      path: AppRoutes.incomingBookingCall,
      builder: (context, state) {
        final extra = state.extra;
        final details = extra is Map<String, dynamic> ? extra : null;
        final bookingId = extra is String
            ? extra
            : details?['bookingId'] as String?;
        final callId = details?['callId'] as String?;
        if (bookingId == null || bookingId.isEmpty) {
          return const PassengerShellScreen();
        }
        return IncomingCallScreen(bookingId: bookingId, callId: callId);
      },
    ),
  ],
);

class _AccountRestoredRedirect extends StatefulWidget {
  const _AccountRestoredRedirect();

  @override
  State<_AccountRestoredRedirect> createState() =>
      _AccountRestoredRedirectState();
}

class _AccountRestoredRedirectState extends State<_AccountRestoredRedirect> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.splash);
      });
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
