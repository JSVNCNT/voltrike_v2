import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/booking.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../data/repositories/driver_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/dashboard_widgets.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';

class DriverDashboardScreen extends ConsumerWidget {
  const DriverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = AuthRepository();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Driver not signed in.')));
    }

    final driverRepository = DriverRepository();
    return Scaffold(
      appBar: AppAppBar(
        title: 'Dashboard',
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: driverRepository.driverStream(user.uid),
        builder: (context, driverSnapshot) {
          if (driverSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (driverSnapshot.hasError) {
            return Center(
              child: Text(DomainErrorMapper.message(driverSnapshot.error!)),
            );
          }

          final driver = driverSnapshot.data;
          if (driver == null) {
            return const Center(child: Text('Driver profile not found.'));
          }

          return StreamBuilder<List<Booking>>(
            stream: BookingRepository().bookingsForDriver(user.uid),
            builder: (context, bookingSnapshot) {
              if (bookingSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (bookingSnapshot.hasError) {
                return Center(
                  child: Text(
                    DomainErrorMapper.message(bookingSnapshot.error!),
                  ),
                );
              }

              final bookings = bookingSnapshot.data ?? const <Booking>[];
              final completedTrips = bookings
                  .where(
                    (booking) => booking.status == BookingStatus.completed,
                  )
                  .length;
              final cancelledTrips = bookings
                  .where(
                    (booking) => booking.status == BookingStatus.cancelled,
                  )
                  .length;
              final currentBooking = _activeBooking(bookings);
              final totalEarnings = bookings.fold<double>(0, (total, booking) {
                return booking.status == BookingStatus.completed
                    ? total + booking.amountDue
                    : total;
              });

              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    FutureBuilder(
                      future: UserRepository().getUser(user.uid),
                      builder: (context, userSnapshot) {
                        return DashboardIdentityCard(
                          eyebrow: 'Driver dashboard',
                          name:
                              userSnapshot.data?.fullName ??
                              user.displayName ??
                              'Driver',
                          statusLabel: driver.isOnline ? 'Online' : 'Offline',
                          statusColor: driver.isOnline
                              ? AppColors.success
                              : AppColors.textSecondary,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    DashboardSection(
                      title: 'Performance',
                      subtitle: 'Your current VolTrike activity',
                      child: DashboardMetricGrid(
                        children: [
                          DashboardMetricCard(
                            icon: Icons.star_rounded,
                            value: driver.rating.toStringAsFixed(1),
                            label: 'Rating',
                            color: AppColors.rating,
                          ),
                          DashboardMetricCard(
                            icon: Icons.check_circle_outline_rounded,
                            value: '$completedTrips',
                            label: 'Completed',
                            color: AppColors.success,
                          ),
                          DashboardMetricCard(
                            icon: Icons.cancel_outlined,
                            value: '$cancelledTrips',
                            label: 'Cancelled',
                            color: AppColors.error,
                          ),
                          DashboardMetricCard(
                            icon: Icons.route_rounded,
                            value: '${bookings.length}',
                            label: 'All trips',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    DashboardSection(
                      title: 'Earnings',
                      child: DashboardMoneySummary(
                        primaryLabel: 'Completed-trip amount',
                        primaryValue: _currency(totalEarnings),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _DriverRatingsCard(
                      driverId: driver.uid,
                      aggregateRating: driver.rating,
                      ratingCount: driver.ratingCount,
                    ),
                    const SizedBox(height: 24),
                    DashboardSection(
                      title: 'Current trip',
                      child: DashboardTripCard(
                        booking: currentBooking,
                        primaryAction: currentBooking == null
                            ? null
                            : FilledButton.icon(
                                onPressed: () => context.push(
                                  AppRoutes.driverBookingTracking,
                                  extra: currentBooking.bookingId,
                                ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Open trip'),
                              ),
                        secondaryAction: currentBooking == null
                            ? null
                            : OutlinedButton.icon(
                                onPressed: () => showRideReportDialog(
                                  context: context,
                                  booking: currentBooking,
                                  reporterIsDriver: true,
                                ),
                                icon: const Icon(
                                  Icons.assignment_late_outlined,
                                ),
                                label: const Text('Report'),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    DashboardSection(
                      title: 'Driver tools',
                      child: Card(
                        child: Column(
                          children: [
                            ListTile(
                              minTileHeight: 64,
                              leading: const Icon(
                                Icons.account_balance_wallet_outlined,
                                color: AppColors.primary,
                              ),
                              title: const Text('Earnings details'),
                              subtitle: const Text(
                                'View today, week, month, and total summaries',
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                              onTap: () => context.push(
                                AppRoutes.driverEarnings,
                                extra: driver.uid,
                              ),
                            ),
                            const Divider(),
                            SwitchListTile(
                              secondary: Icon(
                                driver.isOnline
                                    ? Icons.location_on_rounded
                                    : Icons.location_off_outlined,
                                color: driver.isOnline
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                              title: Text(
                                driver.isOnline ? 'Available' : 'Unavailable',
                              ),
                              subtitle: Text(
                                driver.isOnline
                                    ? 'You can receive nearby booking requests.'
                                    : 'Go online when you are ready to drive.',
                              ),
                              value: driver.isOnline,
                              onChanged: (online) async {
                                if (online) {
                                  await driverRepository.goOnline(driver.uid);
                                } else {
                                  await driverRepository.goOffline(driver.uid);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DriverRatingsCard extends StatelessWidget {
  const _DriverRatingsCard({
    required this.driverId,
    required this.aggregateRating,
    required this.ratingCount,
  });

  final String driverId;
  final double aggregateRating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    return DashboardSection(
      title: 'Passenger feedback',
      child: StreamBuilder<List<DriverRating>>(
        stream: DriverRatingRepository().driverRatings(driverId),
        builder: (context, snapshot) {
          final recent = snapshot.data ?? const <DriverRating>[];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.rating),
                      const SizedBox(width: 8),
                      Text(
                        aggregateRating.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ] else if (snapshot.hasError) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Recent feedback could not be refreshed.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ] else if (recent.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No passenger feedback yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ] else
                    for (final rating in recent.take(3)) ...[
                      const Divider(height: 28),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rating.rating}/5',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: AppColors.rating,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              rating.comment.isEmpty
                                  ? 'Passenger left a star rating.'
                                  : rating.comment,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Booking? _activeBooking(List<Booking> bookings) {
  for (final booking in bookings) {
    if (booking.status != BookingStatus.completed &&
        booking.status != BookingStatus.cancelled) {
      return booking;
    }
  }
  return null;
}

String _currency(double value) {
  return NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value);
}
