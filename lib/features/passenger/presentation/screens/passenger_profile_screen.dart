import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../data/models/app_user.dart';
import '../../../../data/models/passenger.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/emergency_contacts_card.dart';
import '../../../common/presentation/widgets/profile_widgets.dart';

class PassengerProfileScreen extends ConsumerWidget {
  const PassengerProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final firebaseUser = AuthRepository().currentUser;
    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(child: Text('Passenger not signed in.')),
      );
    }

    return StreamBuilder<AppUser?>(
      stream: UserRepository().userStream(firebaseUser.uid),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (userSnapshot.hasError) {
          return _ProfileError(error: userSnapshot.error!);
        }

        final appUser = userSnapshot.data;
        if (appUser == null) {
          return const Scaffold(
            body: Center(child: Text('User profile not found.')),
          );
        }

        return StreamBuilder<Passenger?>(
          stream: PassengerRepository().passengerStream(appUser.uid),
          builder: (context, passengerSnapshot) {
            if (passengerSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (passengerSnapshot.hasError) {
              return _ProfileError(error: passengerSnapshot.error!);
            }

            final passenger = passengerSnapshot.data;
            if (passenger == null) {
              return const Scaffold(
                body: Center(child: Text('Passenger profile not found.')),
              );
            }

            return Scaffold(
              appBar: AppAppBar(
                title: 'Profile',
                actions: [
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      context.push(AppRoutes.passengerSettings);
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    ProfileIdentityHeader(
                      name: appUser.fullName,
                      subtitle: appUser.email,
                      photoUrl: appUser.profileImage,
                      statusLabel: appUser.isActive ? 'Active' : 'Inactive',
                      statusColor: appUser.isActive
                          ? semantic.success
                          : colors.error,
                    ),
                    const SizedBox(height: 24),
                    ProfileSection(
                      title: 'Account information',
                      children: [
                        ProfileInfoTile(
                          icon: Icons.phone_outlined,
                          label: 'Phone number',
                          value: _available(appUser.phoneNumber),
                        ),
                        if (appUser.dateOfBirth != null)
                          ProfileInfoTile(
                            icon: Icons.cake_outlined,
                            label: 'Date of birth',
                            value: _date(appUser.dateOfBirth!),
                          ),
                        ProfileInfoTile(
                          icon: appUser.emailVerified
                              ? Icons.verified_outlined
                              : Icons.warning_amber_rounded,
                          label: 'Email verification',
                          value: appUser.emailVerified
                              ? 'Verified'
                              : 'Not verified',
                          iconColor: appUser.emailVerified
                              ? semantic.success
                              : semantic.warning,
                        ),
                        ProfileInfoTile(
                          icon: Icons.calendar_today_outlined,
                          label: 'Member since',
                          value: _date(appUser.createdAt),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    EmergencyContactsCard(userId: appUser.uid),
                    const SizedBox(height: 24),
                    ProfileSection(
                      title: 'Passenger activity',
                      children: [
                        ProfileInfoTile(
                          icon: Icons.route_outlined,
                          label: 'Total trips',
                          value: '${passenger.totalTrips}',
                        ),
                        ProfileInfoTile(
                          icon: Icons.star_outline_rounded,
                          label: 'Passenger rating',
                          value: '${passenger.rating.toStringAsFixed(1)} / 5',
                          iconColor: semantic.rating,
                        ),
                        ProfileInfoTile(
                          icon: Icons.favorite_outline_rounded,
                          label: 'Favorite locations',
                          value: '${passenger.favoriteLocations.length}',
                          iconColor: colors.error,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
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
