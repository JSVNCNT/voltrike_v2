import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/driver_repository.dart';

/// ===========================================================================
/// Driver Profile Screen
///
/// Displays the authenticated driver's profile.
///
/// Shows:
/// • Profile Photo
/// • Driver Status
/// • Driver Information
/// • Driver Statistics
///
/// Settings are accessible from the AppBar.
/// ===========================================================================
class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final auth = AuthRepository();

    final user = auth.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Driver not signed in.',
          ),
        ),
      );
    }

    return StreamBuilder(
      stream: DriverRepository().driverStream(
        user.uid,
      ),
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child:
                  CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title:
                  const Text('Driver Profile'),
            ),
            body: Center(
              child: Text(
                snapshot.error.toString(),
              ),
            ),
          );
        }

        final driver = snapshot.data;

        if (driver == null) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Driver profile not found.',
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Driver Profile',
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.settings,
                ),
                onPressed: () {
                  context.push(
                    AppRoutes.driverSettings,
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                children: [
                  //----------------------------------------------------------------
                  // Profile
                  //----------------------------------------------------------------

                  CircleAvatar(
                    radius: 60,
                    backgroundImage:
                        driver.profilePhotoUrl
                                .isNotEmpty
                            ? NetworkImage(
                                driver
                                    .profilePhotoUrl,
                              )
                            : null,
                    child:
                        driver.profilePhotoUrl
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

                  Chip(
                    avatar: Icon(
                      driver.isOnline
                          ? Icons.circle
                          : Icons.circle_outlined,
                      color:
                          driver.isOnline
                              ? Colors.green
                              : Colors.red,
                      size: 16,
                    ),
                    label: Text(
                      driver.isOnline
                          ? 'ONLINE'
                          : 'OFFLINE',
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  //----------------------------------------------------------------
                  // Driver Information
                  //----------------------------------------------------------------

                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              const Icon(Icons.groups),
                          title:
                              const Text('TODA ID'),
                          subtitle: Text(
                            driver.todaId,
                          ),
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading: const Icon(
                            Icons.directions_car,
                          ),
                          title: const Text(
                            'Vehicle ID',
                          ),
                          subtitle: Text(
                            driver.vehicleId,
                          ),
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading:
                              const Icon(Icons.badge),
                          title: const Text(
                            'License Number',
                          ),
                          subtitle: Text(
                            driver.licenseNumber,
                          ),
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading:
                              const Icon(Icons.event),
                          title: const Text(
                            'License Expiry',
                          ),
                          subtitle: Text(
                            driver.licenseExpiry
                                .toLocal()
                                .toString()
                                .split(' ')
                                .first,
                          ),
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading: Icon(
                            driver.isApproved
                                ? Icons
                                    .check_circle
                                : Icons.pending,
                            color:
                                driver.isApproved
                                    ? Colors.green
                                    : Colors.orange,
                          ),
                          title: const Text(
                            'Approval Status',
                          ),
                          subtitle: Text(
                            driver.driverStatus
                                .toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  //----------------------------------------------------------------
                  // Statistics
                  //----------------------------------------------------------------

                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.star,
                            color: Colors.amber,
                          ),
                          title: const Text(
                            'Average Rating',
                          ),
                          trailing: Text(
                            driver.rating
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

                        const Divider(height: 1),

                        ListTile(
                          leading: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          title: const Text(
                            'Completed Trips',
                          ),
                          trailing: Text(
                            driver.completedTrips
                                .toString(),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),

                        const Divider(height: 1),

                        ListTile(
                          leading: const Icon(
                            Icons.payments,
                            color: Colors.green,
                          ),
                          title: const Text(
                            'Total Earnings',
                          ),
                          trailing: Text(
                            '₱${driver.totalEarnings.toStringAsFixed(2)}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              color:
                                  Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}