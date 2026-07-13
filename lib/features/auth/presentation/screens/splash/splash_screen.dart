import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../presentation/providers/splash_provider.dart';
import '../../../presentation/controllers/splash_controller.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref
          .read(splashControllerProvider.notifier)
          .checkSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SplashDestination>>(
      splashControllerProvider,
      (previous, next) {
        next.whenData((destination) {
          switch (destination) {
            case SplashDestination.intro:
              context.go(AppRoutes.intro);
              break;

            case SplashDestination.verifyEmail:
              context.go(
                AppRoutes.emailVerification,
              );
              break;

            case SplashDestination.passengerHome:
              context.go(
                AppRoutes.passengerHome,
              );
              break;

            case SplashDestination.driverHome:
              context.go(
                AppRoutes.driverHome,
              );
              break;
          }
        });
      },
    );

    return const AuthScaffold(
      backgroundColor: AppColors.primary,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          AuthLogo(
            logoSize: 120,
            textColor: AppColors.textWhite,
            taglineColor: Colors.white70,
          ),

          SizedBox(
            height: AppConstants.defaultPadding * 2,
          ),

          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}