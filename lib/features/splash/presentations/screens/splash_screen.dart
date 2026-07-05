import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Show splash for a short moment.
      await Future.delayed(const Duration(milliseconds: 1800));

      if (!mounted || _navigated) return;

      _navigated = true;

      /*
      ===========================================================
      STEP 1 (Current)
      ===========================================================

      For now always go to Intro.

      ===========================================================
      STEP 2 (Authentication)
      ===========================================================

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        context.go('/intro');
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role = doc['role'];

      if (role == 'driver') {
        context.go('/driver');
      } else {
        context.go('/passenger');
      }

      ===========================================================
      */

      context.go('/intro');
    } catch (_) {
      if (!mounted) return;
      context.go('/intro');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                ),

                const SizedBox(height: 28),

                const Text(
                  'VolTrike',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: .5,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Clean Community Mobility',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: .4,
                  ),
                ),

                const SizedBox(height: 42),

                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}