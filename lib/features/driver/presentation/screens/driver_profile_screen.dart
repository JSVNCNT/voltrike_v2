import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/emergency_contacts_card.dart';
import '../../../common/presentation/widgets/profile_widgets.dart';

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseUser = AuthRepository().currentUser;
    if (firebaseUser == null) {
      return const Scaffold(body: Center(child: Text('Driver not signed in.')));
    }

    return StreamBuilder(
      stream: DriverRepository().driverStream(firebaseUser.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _ProfileError(error: snapshot.error!);
        }

        final driver = snapshot.data;
        if (driver == null) {
          return const Scaffold(
            body: Center(child: Text('Driver profile not found.')),
          );
        }

        return Scaffold(
          appBar: AppAppBar(
            title: 'Profile',
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push(AppRoutes.driverSettings),
              ),
            ],
          ),
          body: FutureBuilder(
            future: UserRepository().getUser(firebaseUser.uid),
            builder: (context, userSnapshot) {
              final appUser = userSnapshot.data;
              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ProfileIdentityHeader(
                      name:
                          appUser?.fullName ??
                          firebaseUser.displayName ??
                          'VolTrike driver',
                      subtitle: appUser?.email ?? firebaseUser.email ?? '',
                      photoUrl: driver.profilePhotoUrl,
                      statusLabel: driver.isOnline ? 'Online' : 'Offline',
                      statusColor: driver.isOnline
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 24),
                    ProfileSection(
                      title: 'Driver information',
                      children: [
                        ProfileInfoTile(
                          icon: Icons.groups_outlined,
                          label: 'TODA',
                          value: _available(driver.todaId),
                        ),
                        if (appUser?.dateOfBirth != null)
                          ProfileInfoTile(
                            icon: Icons.cake_outlined,
                            label: 'Date of birth',
                            value: _date(appUser!.dateOfBirth!),
                          ),
                        ProfileInfoTile(
                          icon: Icons.electric_rickshaw_outlined,
                          label: 'Vehicle ID',
                          value: _available(driver.vehicleId),
                        ),
                        ProfileInfoTile(
                          icon: Icons.badge_outlined,
                          label: 'License number',
                          value: _available(driver.licenseNumber),
                        ),
                        ProfileInfoTile(
                          icon: Icons.event_outlined,
                          label: 'License expiry',
                          value: _date(driver.licenseExpiry),
                          iconColor: driver.licenseExpiry.isBefore(
                            DateTime.now(),
                          )
                              ? AppColors.error
                              : AppColors.primary,
                        ),
                        ProfileInfoTile(
                          icon: driver.isApproved
                              ? Icons.verified_outlined
                              : Icons.pending_outlined,
                          label: 'Approval status',
                          value: _titleCase(driver.driverStatus),
                          iconColor: driver.isApproved
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    EmergencyContactsCard(userId: firebaseUser.uid),
                    const SizedBox(height: 24),
                    ProfileSection(
                      title: 'Performance',
                      children: [
                        ProfileInfoTile(
                          icon: Icons.star_outline_rounded,
                          label: 'Average rating',
                          value:
                              '${driver.rating.toStringAsFixed(1)} / 5 '
                              '(${driver.ratingCount} ratings)',
                          iconColor: AppColors.rating,
                        ),
                        ProfileInfoTile(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Completed trips',
                          value: '${driver.completedTrips}',
                          iconColor: AppColors.success,
                        ),
                        ProfileInfoTile(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Profile earnings total',
                          value: NumberFormat.currency(
                            locale: 'en_PH',
                            symbol: '₱',
                          ).format(driver.totalEarnings),
                          iconColor: AppColors.success,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Profile'),
      body: Center(child: Text(DomainErrorMapper.message(error))),
    );
  }
}

String _date(DateTime value) {
  return DateFormat('MMMM d, yyyy').format(value.toLocal());
}

String _available(String value) {
  return value.trim().isEmpty ? 'Not provided' : value;
}

String _titleCase(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
