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
import '../../../../data/repositories/user_repository.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/dashboard_widgets.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';

class PassengerDashboardScreen extends ConsumerWidget {
  const PassengerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = AuthRepository().currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Passenger not signed in.')),
      );
    }

    return Scaffold(
      appBar: const AppAppBar(title: 'Dashboard'),
      body: StreamBuilder<List<Booking>>(
        stream: BookingRepository().bookingsForPassenger(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(DomainErrorMapper.message(snapshot.error!)),
            );
          }

          final trips = [...?snapshot.data]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final recentTrip = trips.isEmpty ? null : trips.first;
          final completedTrips = trips
              .where((booking) => booking.status == BookingStatus.completed)
              .length;
          final pendingTrips = trips
              .where((booking) => booking.status == BookingStatus.pending)
              .length;
          final cancelledTrips = trips
              .where((booking) => booking.status == BookingStatus.cancelled)
              .length;
          final totalSpent = trips
              .where((booking) => booking.status == BookingStatus.completed)
              .fold<double>(0, (total, booking) => total + booking.amountDue);
          final averageFare = completedTrips == 0
              ? 0.0
              : totalSpent / completedTrips;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                FutureBuilder(
                  future: UserRepository().getUser(user.uid),
                  builder: (context, userSnapshot) {
                    return DashboardIdentityCard(
                      eyebrow: 'Welcome back',
                      name:
                          userSnapshot.data?.fullName ??
                          user.displayName ??
                          user.email ??
                          'Passenger',
                    );
                  },
                ),
                const SizedBox(height: 20),
                DashboardSection(
                  title: 'Ride overview',
                  subtitle: 'Your VolTrike activity at a glance',
                  child: DashboardMetricGrid(
                    children: [
                      DashboardMetricCard(
                        icon: Icons.route_rounded,
                        value: '${trips.length}',
                        label: 'Total trips',
                      ),
                      DashboardMetricCard(
                        icon: Icons.check_circle_outline_rounded,
                        value: '$completedTrips',
                        label: 'Completed',
                        color: AppColors.success,
                      ),
                      DashboardMetricCard(
                        icon: Icons.schedule_rounded,
                        value: '$pendingTrips',
                        label: 'Pending',
                        color: AppColors.warning,
                      ),
                      DashboardMetricCard(
                        icon: Icons.cancel_outlined,
                        value: '$cancelledTrips',
                        label: 'Cancelled',
                        color: AppColors.error,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                DashboardSection(
                  title: 'Spending',
                  child: DashboardMoneySummary(
                    primaryLabel: 'Total spent on completed trips',
                    primaryValue: _currency(totalSpent),
                    secondaryLabel: 'Average fare',
                    secondaryValue: _currency(averageFare),
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(height: 24),
                _PassengerRatingsCard(
                  passengerId: user.uid,
                  trips: trips,
                ),
                const SizedBox(height: 24),
                DashboardSection(
                  title: recentTrip == null ? 'Recent trip' : 'Latest trip',
                  child: DashboardTripCard(
                    booking: recentTrip,
                    emptyMessage:
                        'Your latest booking will appear here after you request a ride.',
                    primaryAction: _activeTripAction(context, recentTrip),
                    secondaryAction: _reportAction(context, recentTrip),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget? _activeTripAction(BuildContext context, Booking? booking) {
    if (booking == null ||
        booking.driverId == null ||
        booking.status == BookingStatus.completed ||
        booking.status == BookingStatus.cancelled) {
      return null;
    }
    return FilledButton.icon(
      onPressed: () => context.push(
        AppRoutes.driverTracking,
        extra: booking.bookingId,
      ),
      icon: const Icon(Icons.map_outlined),
      label: const Text('Open trip'),
    );
  }

  Widget? _reportAction(BuildContext context, Booking? booking) {
    if (booking?.driverId == null) return null;
    return OutlinedButton.icon(
      onPressed: () => showRideReportDialog(
        context: context,
        booking: booking!,
        reporterIsDriver: false,
      ),
      icon: const Icon(Icons.assignment_late_outlined),
      label: const Text('Report'),
    );
  }
}

class _PassengerRatingsCard extends StatelessWidget {
  const _PassengerRatingsCard({
    required this.passengerId,
    required this.trips,
  });

  final String passengerId;
  final List<Booking> trips;

  @override
  Widget build(BuildContext context) {
    return DashboardSection(
      title: 'Trip feedback',
      child: StreamBuilder<List<DriverRating>>(
        stream: DriverRatingRepository().passengerRatings(passengerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('Checking trip feedback…')),
                  ],
                ),
              ),
            );
          }

          final ratings = snapshot.data ?? const <DriverRating>[];
          final ratedBookingIds = ratings
              .map((rating) => rating.bookingId)
              .toSet();
          final pending =
              trips
                  .where(
                    (booking) =>
                        booking.status == BookingStatus.completed &&
                        booking.driverId != null &&
                        !ratedBookingIds.contains(booking.bookingId),
                  )
                  .toList()
                ..sort(
                  (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
                    a.completedAt ?? a.updatedAt,
                  ),
                );
          final latest = ratings.isEmpty ? null : ratings.first;
          Booking? latestTrip;
          if (latest != null) {
            for (final trip in trips) {
              if (trip.bookingId == latest.bookingId) {
                latestTrip = trip;
                break;
              }
            }
          }

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppColors.rating,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pending.isEmpty
                              ? 'All completed trips have been reviewed.'
                              : '${pending.length} completed '
                                    '${pending.length == 1 ? 'trip is' : 'trips are'} '
                                    'waiting for your rating.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push(
                        AppRoutes.rateDriver,
                        extra: pending.first.bookingId,
                      ),
                      icon: const Icon(Icons.star_outline_rounded),
                      label: Text(
                        'Rate ${pending.first.driverName ?? 'driver'}',
                      ),
                    ),
                  ],
                  if (latest != null) ...[
                    const Divider(height: 28),
                    Text(
                      '${latest.rating} out of 5'
                      '${latestTrip?.driverName == null ? '' : ' for ${latestTrip!.driverName}'}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (latest.comment.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        latest.comment,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ] else if (pending.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'No ratings submitted yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Saved ratings could not be refreshed. You can still rate '
                      'a completed trip from Trip History.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.warning,
                      ),
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

String _currency(double value) {
  return NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value);
}
