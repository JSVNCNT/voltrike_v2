import 'package:flutter/material.dart';

import '../../../../data/models/app_user.dart';
import '../../../../data/models/driver.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../domain/account_access_policy.dart';
import '../screens/driver_registration/under_review_screen.dart';
import '../screens/suspended_account_screen.dart';

class AccountStatusGate extends StatelessWidget {
  const AccountStatusGate({super.key, required this.child, this.driverAccount});

  final Widget child;

  /// When null, the role is derived from the live user profile.
  final bool? driverAccount;

  @override
  Widget build(BuildContext context) {
    final uid = AuthRepository().currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Sign in to continue.')));
    }

    return StreamBuilder<AppUser?>(
      stream: UserRepository().userStream(uid),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (userSnapshot.hasError) {
          return _StatusLoadError(error: userSnapshot.error);
        }

        final user = userSnapshot.data;
        if (user == null) {
          return const SuspendedAccountScreen(isDriver: false);
        }
        final isDriver = driverAccount ?? user.isDriver;
        if (!user.isActive) {
          return SuspendedAccountScreen(isDriver: isDriver);
        }
        if (!isDriver) return child;

        return StreamBuilder<Driver?>(
          stream: DriverRepository().driverStream(uid),
          builder: (context, driverSnapshot) {
            if (driverSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (driverSnapshot.hasError) {
              return _StatusLoadError(error: driverSnapshot.error);
            }

            final status = AccountAccessPolicy.evaluate(
              user: user,
              driver: driverSnapshot.data,
            );
            return switch (status) {
              AccountAccessStatus.active => child,
              AccountAccessStatus.suspended => const SuspendedAccountScreen(
                isDriver: true,
              ),
              AccountAccessStatus.underReview =>
                const DriverUnderReviewScreen(),
            };
          },
        );
      },
    );
  }
}

class _StatusLoadError extends StatelessWidget {
  const _StatusLoadError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Account status could not be synchronized.\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
