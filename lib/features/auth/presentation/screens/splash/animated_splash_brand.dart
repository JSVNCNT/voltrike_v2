import 'package:flutter/material.dart';

import '../../../../../core/constants/app_assets.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';

class AnimatedSplashBrand extends StatelessWidget {
  const AnimatedSplashBrand({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${AppStrings.appName}, ${AppStrings.appTagline}',
      image: true,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = animation.value;
          final finalImageOpacity = Curves.easeOutCubic.transform(
            _interval(progress, 0.56, 0.72),
          );
          final titleProgress = Curves.easeOutCubic.transform(
            _interval(progress, 0.64, 0.8),
          );
          final taglineProgress = Curves.easeOutCubic.transform(
            _interval(progress, 0.72, 0.86),
          );
          final settleProgress = Curves.easeOutBack.transform(
            _interval(progress, 0.54, 0.76),
          );

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.985 + (0.015 * settleProgress),
                child: SizedBox(
                  width: 230,
                  height: 210,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: finalImageOpacity * 0.16,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                AppColors.primaryLight,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      for (final piece in _pieces)
                        _AnimatedLogoPiece(
                          piece: piece,
                          progress: _interval(progress, piece.begin, piece.end),
                        ),
                      Opacity(
                        opacity: finalImageOpacity,
                        child: const _LogoImage(),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, 8 * (1 - titleProgress)),
                child: Opacity(
                  opacity: titleProgress,
                  child: Text(
                    AppStrings.appName,
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: AppColors.textWhite,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Transform.translate(
                offset: Offset(0, 6 * (1 - taglineProgress)),
                child: Opacity(
                  opacity: taglineProgress,
                  child: Text(
                    AppStrings.appTagline,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedLogoPiece extends StatelessWidget {
  const _AnimatedLogoPiece({required this.piece, required this.progress});

  final _LogoPiece piece;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOutCubic.transform(progress);
    return Transform.translate(
      offset: Offset(
        piece.offset.dx * (1 - eased),
        piece.offset.dy * (1 - eased),
      ),
      child: Transform.rotate(
        angle: piece.rotation * (1 - eased),
        child: Transform.scale(
          scale: 0.9 + (0.1 * eased),
          child: Opacity(
            opacity: eased,
            child: ClipPath(
              clipper: _PolygonClipper(piece.points),
              child: const _LogoImage(),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.logoLight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.points);

  final List<Offset> points;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final x = point.dx * size.width;
      final y = point.dy * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(_PolygonClipper oldClipper) => false;
}

class _LogoPiece {
  const _LogoPiece({
    required this.points,
    required this.offset,
    required this.rotation,
    required this.begin,
    required this.end,
  });

  final List<Offset> points;
  final Offset offset;
  final double rotation;
  final double begin;
  final double end;
}

const _pieces = <_LogoPiece>[
  _LogoPiece(
    points: [Offset(0, 0), Offset(0.62, 0), Offset(0.53, 0.43), Offset(0, 0.5)],
    offset: Offset(-14, -10),
    rotation: -0.055,
    begin: 0,
    end: 0.3,
  ),
  _LogoPiece(
    points: [
      Offset(0, 0.42),
      Offset(0.45, 0.35),
      Offset(0.52, 1),
      Offset(0, 1),
    ],
    offset: Offset(-16, 8),
    rotation: 0.045,
    begin: 0.08,
    end: 0.4,
  ),
  _LogoPiece(
    points: [
      Offset(0.4, 0.3),
      Offset(0.72, 0.26),
      Offset(0.68, 1),
      Offset(0.48, 1),
    ],
    offset: Offset(0, 15),
    rotation: -0.035,
    begin: 0.16,
    end: 0.5,
  ),
  _LogoPiece(
    points: [Offset(0.58, 0), Offset(1, 0), Offset(1, 0.6), Offset(0.65, 0.54)],
    offset: Offset(14, -12),
    rotation: 0.06,
    begin: 0.24,
    end: 0.56,
  ),
  _LogoPiece(
    points: [
      Offset(0.62, 0.48),
      Offset(1, 0.42),
      Offset(1, 1),
      Offset(0.64, 1),
    ],
    offset: Offset(17, 10),
    rotation: -0.045,
    begin: 0.32,
    end: 0.64,
  ),
];

double _interval(double value, double begin, double end) {
  return ((value - begin) / (end - begin)).clamp(0, 1).toDouble();
}
