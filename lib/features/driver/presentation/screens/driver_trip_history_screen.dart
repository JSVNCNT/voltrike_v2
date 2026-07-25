import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/empty_state.dart';
import '../../../ride/tracking/widgets/expandable_trip_card.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../controllers/driver_trip_history_controller.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/report_repository.dart';

class DriverTripHistoryScreen extends ConsumerWidget {
  const DriverTripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(driverTripHistoryProvider);
    return Scaffold(
      appBar: const AppAppBar(title: 'Trip History'),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (bookings) => bookings.isEmpty
            ? const EmptyState(title: 'No Trips Yet', message: 'Completed trips appear here.', icon: Icons.receipt_long_outlined)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: bookings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  final user = AuthRepository().currentUser;
                  return ExpandableTripCard(
                    booking: booking,
                    otherPartyLabel: 'Passenger',
                    onReport: user == null ? null : () => showDialog<void>(context: context, builder: (_) => ReportRideDialog(onSubmit: (category, details) => ReportRepository().create(bookingId: booking.bookingId, reporterId: user.uid, reportedUserId: booking.passengerId, category: category, details: details))),
                  );
                },
              ),
      ),
    );
  }
}
