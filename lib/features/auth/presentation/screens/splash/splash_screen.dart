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
  Timer? _minimumSplashTimer;
  SplashRecovery? _pendingRecovery;
  bool _animationStarted = false;
  bool _minimumSplashElapsed = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addStatusListener((status) {
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
    _minimumSplashTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _minimumSplashElapsed = true;
      });
      _navigateIfReady();
    });
    unawaited(_precacheAndStartAnimation(reduceMotion: reduceMotion));
  }

  Future<void> _precacheAndStartAnimation({required bool reduceMotion}) async {
    try {
      await precacheImage(const AssetImage(AppAssets.logoLight), context);
    } catch (_) {
      // Image.asset reports an actionable error if the packaged asset is
      // unavailable; the session recovery must not become blocked by it.
    }
    if (!mounted) return;
    if (reduceMotion) {
      _animationController.value = 1;
    } else {
      _animationController.forward();
    }
    unawaited(_warmCommonLaunchAssets());
  }

  Future<void> _warmCommonLaunchAssets() async {
    // Use the branded animation window to prepare the most common first-screen
    // imagery. This remains best-effort and never blocks session recovery.
    final assets = <String>[AppAssets.logoDark];
    await Future.wait(
      assets.map((asset) async {
        try {
          await precacheImage(AssetImage(asset), context);
        } catch (_) {
          // A missing optional image should not prevent startup navigation.
        }
      }),
    );
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
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, _) => CustomPaint(
                  painter: _AerodynamicBackdropPainter(
                    progress: _animationController.value,
                  ),
                ),
              ),
            ),
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
                        showLoading: _minimumSplashElapsed,
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
        !_minimumSplashElapsed ||
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
    _minimumSplashTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }
}

class _SplashStatus extends StatelessWidget {
  const _SplashStatus({
    required this.showLoading,
    required this.state,
    required this.onRetry,
  });

  final bool showLoading;
  final AsyncValue<SplashRecovery> state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: () => AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: showLoading
            ? const Column(
                key: ValueKey('extended-splash-loading'),
                children: [
                  _AirRibbonLoader(),
                  SizedBox(height: 13),
                  Text(
                    'Restoring session…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              )
            : const SizedBox(
                key: ValueKey('initial-splash-loading'),
                height: 50,
              ),
      ),
      data: (_) => const SizedBox(height: 50),
      error: (_, _) => showLoading
          ? Column(
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
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            )
          : const SizedBox(height: 50),
    );
  }
}

class _AirRibbonLoader extends StatefulWidget {
  const _AirRibbonLoader();

  @override
  State<_AirRibbonLoader> createState() => _AirRibbonLoaderState();
}

class _AirRibbonLoaderState extends State<_AirRibbonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _AirRibbonPainter(progress: _controller.value),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _AirRibbonPainter extends CustomPainter {
  const _AirRibbonPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 82, size.height / 24);

    final paths = <Path>[
      Path()
        ..moveTo(2, 6)
        ..cubicTo(22, 0, 42, 12, 80, 5),
      Path()
        ..moveTo(2, 12)
        ..cubicTo(28, 6, 48, 18, 80, 11),
      Path()
        ..moveTo(2, 19)
        ..cubicTo(25, 13, 48, 25, 80, 18),
    ];
    const opacities = [0.86, 0.66, 0.46];
    const phases = [0.0, 26.0, 52.0];

    for (var index = 0; index < paths.length; index++) {
      _drawDashedPath(
        canvas,
        paths[index],
        Paint()
          ..color = Colors.white.withValues(alpha: opacities[index])
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
        dashLength: 34,
        gapLength: 46,
        offset: ((1 - progress) * 80) + phases[index],
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AirRibbonPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AerodynamicBackdropPainter extends CustomPainter {
  const _AerodynamicBackdropPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final reveal = Curves.easeOutCubic.transform(
      ((progress - 0.04) / 0.48).clamp(0, 1).toDouble(),
    );
    if (reveal == 0) return;

    canvas.save();
    canvas.scale(size.width / 390, size.height / 694);

    final darkPaint = Paint()
      ..color = const Color(0xFF001112).withValues(alpha: 0.20 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final tealPaint = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.20 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final palePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08 * reveal)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final darkPaths = <Path>[
      Path()
        ..moveTo(12, 188)
        ..lineTo(82, 188)
        ..cubicTo(111, 188, 124, 205, 117, 220)
        ..cubicTo(112, 230, 104, 234, 94, 234),
      Path()
        ..moveTo(8, 486)
        ..lineTo(100, 486)
        ..cubicTo(130, 486, 143, 503, 136, 519)
        ..cubicTo(131, 530, 122, 534, 112, 534),
      Path()
        ..moveTo(302, 226)
        ..lineTo(340, 226)
        ..cubicTo(360, 226, 368, 239, 363, 251)
        ..cubicTo(359, 259, 353, 263, 346, 263),
    ];
    for (final path in darkPaths) {
      canvas.drawPath(path, darkPaint);
    }

    final topLeaf = Path()
      ..moveTo(279, 113)
      ..cubicTo(309, 84, 351, 83, 365, 87)
      ..cubicTo(364, 125, 353, 166, 316, 175)
      ..cubicTo(292, 181, 269, 168, 268, 145)
      ..cubicTo(267, 133, 272, 122, 279, 113)
      ..close();
    final lowerLeaf = Path()
      ..moveTo(30, 523)
      ..cubicTo(48, 502, 74, 497, 92, 511)
      ..cubicTo(85, 532, 64, 545, 44, 535)
      ..cubicTo(38, 532, 33, 528, 30, 523)
      ..close();
    canvas.drawPath(topLeaf, tealPaint);
    canvas.drawPath(lowerLeaf, tealPaint);
    canvas.drawLine(const Offset(265, 182), const Offset(327, 117), tealPaint);
    canvas.drawLine(const Offset(32, 523), const Offset(75, 522), tealPaint);

    final flowPaths = <Path>[
      Path()
        ..moveTo(8, 216)
        ..lineTo(68, 216)
        ..cubicTo(96, 216, 106, 226, 102, 237),
      Path()
        ..moveTo(12, 454)
        ..lineTo(72, 454)
        ..cubicTo(99, 454, 109, 446, 118, 434),
      Path()
        ..moveTo(288, 508)
        ..lineTo(390, 508),
      Path()
        ..moveTo(292, 178)
        ..lineTo(390, 178),
    ];
    final phase = (1 - progress) * 37;
    for (var index = 0; index < flowPaths.length; index++) {
      _drawDashedPath(
        canvas,
        flowPaths[index],
        index.isEven ? tealPaint : palePaint,
        dashLength: 24,
        gapLength: 18,
        offset: phase + (index * 11),
      );
    }

    canvas.drawLine(const Offset(56, 313), const Offset(84, 313), palePaint);
    canvas.drawLine(const Offset(306, 351), const Offset(329, 351), palePaint);
    canvas.drawLine(const Offset(78, 386), const Offset(98, 386), tealPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AerodynamicBackdropPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

void _drawDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dashLength,
  required double gapLength,
  required double offset,
}) {
  final patternLength = dashLength + gapLength;
  for (final metric in path.computeMetrics()) {
    var distance = -patternLength + (offset % patternLength);
    while (distance < metric.length) {
      final start = distance.clamp(0, metric.length).toDouble();
      final end = (distance + dashLength).clamp(0, metric.length).toDouble();
      if (end > start) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      }
      distance += patternLength;
    }
  }
}
