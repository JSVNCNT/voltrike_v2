import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/models/app_user.dart';
import '../../../../data/models/passenger.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/passenger_repository.dart';
import '../../../../data/repositories/user_repository.dart';

/// ===========================================================================
/// Passenger Profile Screen
///
/// Displays the authenticated passenger's profile.
///
/// Shows:
/// • Profile Photo
/// • Passenger Information
/// • Passenger Statistics
///
/// Settings are accessible from the AppBar.
/// ===========================================================================
class PassengerProfileScreen extends ConsumerWidget {
  const PassengerProfileScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final auth = AuthRepository();

    final firebaseUser =
        auth.currentUser;

    if (firebaseUser == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Passenger not signed in.',
          ),
        ),
      );
    }

    return StreamBuilder<AppUser?>(
      stream: UserRepository().userStream(
        firebaseUser.uid,
      ),
      builder: (
        context,
        userSnapshot,
      ) {
        if (userSnapshot.connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        if (userSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Passenger Profile',
              ),
            ),
            body: Center(
              child: Text(
                userSnapshot.error
                    .toString(),
              ),
            ),
          );
        }

        final appUser =
            userSnapshot.data;

        if (appUser == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'User profile not found.',
              ),
            ),
          );
        }

        return StreamBuilder<
            Passenger?>(
          stream:
              PassengerRepository()
                  .passengerStream(
            appUser.uid,
          ),
          builder: (
            context,
            passengerSnapshot,
          ) {
            if (passengerSnapshot
                    .connectionState ==
                ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child:
                      CircularProgressIndicator(),
                ),
              );
            }

            if (passengerSnapshot
                .hasError) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text(
                    'Passenger Profile',
                  ),
                ),
                body: Center(
                  child: Text(
                    passengerSnapshot
                        .error
                        .toString(),
                  ),
                ),
              );
            }

            final passenger =
                passengerSnapshot.data;

            if (passenger == null) {
              return const Scaffold(
                body: Center(
                  child: Text(
                    'Passenger profile not found.',
                  ),
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Passenger Profile',
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.settings,
                    ),
                    onPressed: () {
                      context.push(
                        AppRoutes
                            .passengerSettings,
                      );
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child:
                    SingleChildScrollView(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Column(
                    children: [
                      //----------------------------------------------------------------
                      // Profile
                      //----------------------------------------------------------------

                      CircleAvatar(
                        radius: 60,
                        backgroundImage:
                            appUser.profileImage
                                    .isNotEmpty
                                ? NetworkImage(
                                    appUser
                                        .profileImage,
                                  )
                                : null,
                        child:
                            appUser.profileImage
                                    .isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 60,
                                  )
                                : null,
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      Text(
                        appUser.fullName,
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        appUser.email,
                        style:
                            const TextStyle(
                          color:
                              Colors.grey,
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                                        //----------------------------------------------------------------
                      // Account Information
                      //----------------------------------------------------------------

                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(
                                Icons.phone,
                              ),
                              title: const Text(
                                'Phone Number',
                              ),
                              subtitle: Text(
                                appUser.phoneNumber,
                              ),
                            ),

                            const Divider(
                              height: 1,
                            ),

                            ListTile(
                              leading: Icon(
                                appUser.isActive
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color:
                                    appUser.isActive
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              title: const Text(
                                'Account Status',
                              ),
                              subtitle: Text(
                                appUser.isActive
                                    ? 'Active'
                                    : 'Inactive',
                              ),
                            ),

                            const Divider(
                              height: 1,
                            ),

                            ListTile(
                              leading: Icon(
                                appUser.emailVerified
                                    ? Icons.verified
                                    : Icons.warning,
                                color:
                                    appUser.emailVerified
                                        ? Colors.green
                                        : Colors.orange,
                              ),
                              title: const Text(
                                'Email Verification',
                              ),
                              subtitle: Text(
                                appUser.emailVerified
                                    ? 'Verified'
                                    : 'Not Verified',
                              ),
                            ),

                            const Divider(
                              height: 1,
                            ),

                            ListTile(
                              leading: const Icon(
                                Icons.calendar_today,
                              ),
                              title: const Text(
                                'Member Since',
                              ),
                              subtitle: Text(
                                appUser.createdAt
                                    .toLocal()
                                    .toString()
                                    .split(
                                      ' ',
                                    )
                                    .first,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                                            //----------------------------------------------------------------
                      // Passenger Statistics
                      //----------------------------------------------------------------

                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(
                                Icons.local_taxi,
                                color: Colors.blue,
                              ),
                              title: const Text(
                                'Total Trips',
                              ),
                              trailing: Text(
                                passenger.totalTrips
                                    .toString(),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),

                            const Divider(
                              height: 1,
                            ),

                            ListTile(
                              leading: const Icon(
                                Icons.star,
                                color: Colors.amber,
                              ),
                              title: const Text(
                                'Passenger Rating',
                              ),
                              trailing: Text(
                                passenger.rating
                                    .toStringAsFixed(
                                  1,
                                ),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),

                            const Divider(
                              height: 1,
                            ),

                            ListTile(
                              leading: const Icon(
                                Icons.favorite,
                                color: Colors.red,
                              ),
                              title: const Text(
                                'Favorite Locations',
                              ),
                              trailing: Text(
                                passenger
                                    .favoriteLocations
                                    .length
                                    .toString(),
                                style:
                                    const TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      Center(
                        child: Text(
                          'Voltrike Passenger v1.0.0',
                          style: TextStyle(
                            color:
                                Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}