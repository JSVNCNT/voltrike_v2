import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/constants/app_assets.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../presentation/controllers/splash_controller.dart';
import '../../../presentation/providers/splash_provider.dart';
import 'animated_splash_brand.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  SplashRecovery? _pendingRecovery;
  bool _animationStarted = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 850),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _navigateIfReady();
        });

    Future.microtask(() {
      ref.read(splashControllerProvider.notifier).checkSession();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationStarted) return;
    _animationStarted = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _animationController.duration = const Duration(milliseconds: 150);
    }
    unawaited(_precacheAndStartAnimation());
  }

  Future<void> _precacheAndStartAnimation() async {
    try {
      await precacheImage(const AssetImage(AppAssets.logoLight), context);
    } catch (_) {
      // Image.asset reports an actionable error if the packaged asset is
      // unavailable; the session recovery must not become blocked by it.
    }
    if (mounted) _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splashControllerProvider);

    ref.listen<AsyncValue<SplashRecovery>>(splashControllerProvider, (
      previous,
      next,
    ) {
      next.whenData((recovery) {
        _pendingRecovery = recovery;
        _navigateIfReady();
      });
    });

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryDark, Color(0xFF042E30)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: 290,
                height: 290,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryLight.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSplashBrand(animation: _animationController),
                      const SizedBox(height: 34),
                      _SplashStatus(
                        animation: _animationController,
                        state: state,
                        onRetry: () => ref
                            .read(splashControllerProvider.notifier)
                            .checkSession(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateIfReady() {
    if (!mounted ||
        _navigating ||
        !_animationController.isCompleted ||
        _pendingRecovery == null) {
      return;
    }
    _navigating = true;
    final recovery = _pendingRecovery!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

class _SplashStatus extends StatelessWidget {
  const _SplashStatus({
    required this.animation,
    required this.state,
    required this.onRetry,
  });

  final Animation<double> animation;
  final AsyncValue<SplashRecovery> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: () => AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final opacity = ((animation.value - 0.68) / 0.22)
              .clamp(0, 1)
              .toDouble();
          return Opacity(opacity: opacity, child: child);
        },
        child: const Column(
          children: [
            SizedBox(
              width: 23,
              height: 23,
              child: CircularProgressIndicator(
                strokeWidth: 2.25,
                color: AppColors.primaryLight,
                backgroundColor: Colors.white24,
              ),
            ),
            SizedBox(height: 13),
            Text(
              'Restoring your session…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
      data: (_) => const SizedBox(height: 50),
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
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
