import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../ride/tracking/screens/trip_history_detail_screen.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../../ride/tracking/widgets/trip_history_card.dart';
import '../../../ride/tracking/widgets/trip_history_view.dart';
import '../../controllers/driver_trip_history_controller.dart';
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
  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(driverTripHistoryProvider);
    return Scaffold(
      appBar: const AppAppBar(title: 'Trip History'),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(DomainErrorMapper.message(error))),
        data: (bookings) => TripHistoryView(
          bookings: bookings,
          itemBuilder: (context, booking) {
            return TripHistoryCard(
              booking: booking,
              otherPartyLabel: booking.passengerName ?? 'Passenger',
              otherPartyPhotoUrl: booking.passengerPhotoUrl,
              onTap: () => _openTripDetails(context, booking),
            );
          },
        ),
      ),
    );
  }

  void _openTripDetails(BuildContext context, Booking booking) {
    final completed = booking.status == BookingStatus.completed;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (detailContext) => TripHistoryDetailScreen(
          booking: booking,
          driverView: true,
          onReceipt: completed
              ? () => Navigator.of(detailContext).push(
                  MaterialPageRoute(
                    builder: (_) => TripReceiptScreen(
                      bookingId: booking.bookingId,
                      driverView: true,
                    ),
                  ),
                )
              : null,
          onReport: () => showRideReportDialog(
            context: detailContext,
            booking: booking,
            reporterIsDriver: true,
          ),
        ),
      ),
    );
  }
}
