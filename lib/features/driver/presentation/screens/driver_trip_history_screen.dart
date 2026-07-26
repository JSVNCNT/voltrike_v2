import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../common/presentation/widgets/empty_state.dart';
import '../../../ride/tracking/widgets/expandable_trip_card.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../controllers/driver_trip_history_controller.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/report_repository.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../passenger/presentation/screens/trip_receipt_screen.dart';

class DriverTripHistoryScreen extends ConsumerStatefulWidget {
  const DriverTripHistoryScreen({super.key});

  @override
  ConsumerState<DriverTripHistoryScreen> createState() =>
      _DriverTripHistoryScreenState();
}

class _DriverTripHistoryScreenState
    extends ConsumerState<DriverTripHistoryScreen> {
  int _visibleCount = 10;

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(driverTripHistoryProvider);
    return Scaffold(
      appBar: const AppAppBar(title: 'Trip History'),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(DomainErrorMapper.message(error))),
        data: (bookings) => bookings.isEmpty
            ? const EmptyState(title: 'No Trips Yet', message: 'Completed trips appear here.', icon: Icons.receipt_long_outlined)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: (bookings.length > _visibleCount
                        ? _visibleCount
                        : bookings.length) +
                    (bookings.length > _visibleCount ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == _visibleCount) {
                    return OutlinedButton(
                      onPressed: () => setState(() => _visibleCount += 10),
                      child: const Text('Load more trips'),
                    );
                  }
                  final booking = bookings[index];
                  final user = AuthRepository().currentUser;
                  return ExpandableTripCard(
                    booking: booking,
                    otherPartyLabel: booking.passengerName ?? 'Passenger',
                    otherPartyPhotoUrl: booking.passengerPhotoUrl,
                    onReceipt: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TripReceiptScreen(
                          bookingId: booking.bookingId,
                          driverView: true,
                        ),
                      ),
                    ),
                    onReport: user == null ? null : () => showDialog<void>(context: context, builder: (_) => ReportRideDialog(reporterIsDriver: true, onSubmit: (category, details) => ReportRepository().create(bookingId: booking.bookingId, reporterId: user.uid, reportedUserId: booking.passengerId, category: category, details: details))),
                  );
                },
              ),
      ),
    );
  }
}
