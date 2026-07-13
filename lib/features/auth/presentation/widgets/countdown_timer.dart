import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.seconds,
    required this.onFinished,
  });

  final int seconds;
  final VoidCallback onFinished;

  @override
  State<CountdownTimer> createState() =>
      _CountdownTimerState();
}

class _CountdownTimerState
    extends State<CountdownTimer> {
  late int remaining;

  Timer? timer;

  @override
  void initState() {
    super.initState();

    remaining = widget.seconds;

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) return;

        if (remaining <= 1) {
          timer.cancel();
          widget.onFinished();
        } else {
          setState(() {
            remaining--;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String get formatted {
    final minutes =
        (remaining ~/ 60).toString().padLeft(2, '0');

    final seconds =
        (remaining % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatted,
      style: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}