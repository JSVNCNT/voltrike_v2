import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../presentation/controllers/splash_controller.dart';
import '../../../presentation/providers/splash_provider.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(splashControllerProvider.notifier).checkSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splashControllerProvider);

    ref.listen<AsyncValue<SplashRecovery>>(splashControllerProvider, (
      previous,
      next,
    ) {
      next.whenData((recovery) {
        switch (recovery.destination) {
          case SplashDestination.intro:
            context.go(AppRoutes.intro);
            break;

          case SplashDestination.verifyEmail:
            context.go(AppRoutes.emailVerification);
            break;

          case SplashDestination.passengerHome:
            context.go(AppRoutes.passengerHome);
            break;

          case SplashDestination.driverHome:
            context.go(AppRoutes.driverHome);
            break;

          case SplashDestination.driverUnderReview:
            context.go(AppRoutes.driverUnderReview);
            break;

          case SplashDestination.accountSuspended:
            context.go(AppRoutes.accountSuspended);
            break;

          case SplashDestination.passengerActiveBooking:
            context.go(
              AppRoutes.withBookingId(
                AppRoutes.driverTracking,
                recovery.bookingId!,
              ),
              extra: recovery.bookingId,
            );
            break;

          case SplashDestination.driverActiveBooking:
            context.go(
              AppRoutes.withBookingId(
                AppRoutes.driverBookingTracking,
                recovery.bookingId!,
              ),
              extra: recovery.bookingId,
            );
            break;
        }
      });
    });

    return AuthScaffold(
      backgroundColor: AppColors.primaryDark,
      useSurface: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AuthLogo(
            logoSize: 92,
            textColor: AppColors.textWhite,
            taglineColor: Colors.white70,
          ),

          const SizedBox(height: AppConstants.defaultPadding * 2),

          state.when(
            loading: () => const Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Restoring your session…',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            data: (_) => const SizedBox.shrink(),
            error: (_, _) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Unable to restore your session. Check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: AppConstants.defaultPadding),
                FilledButton.tonal(
                  onPressed: () => ref
                      .read(splashControllerProvider.notifier)
                      .checkSession(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
