import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/models/booking_state_machine.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../common/presentation/widgets/app_app_bar.dart';
import '../../../ride/tracking/screens/trip_history_detail_screen.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import '../../../ride/tracking/widgets/trip_history_card.dart';
import '../../../ride/tracking/widgets/trip_history_view.dart';
import 'rating_screen.dart';
import 'trip_receipt_screen.dart';

class PassengerTripHistoryScreen extends ConsumerStatefulWidget {
  const PassengerTripHistoryScreen({super.key});

  @override
  ConsumerState<PassengerTripHistoryScreen> createState() =>
      _PassengerTripHistoryScreenState();
}

class _PassengerTripHistoryScreenState
    extends ConsumerState<PassengerTripHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final user = AuthRepository().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }
    return Scaffold(
      appBar: const AppAppBar(title: 'Trip History'),
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
          final trips = BookingStateMachine.terminalHistory(
            snapshot.data ?? const <Booking>[],
          );
          return StreamBuilder<List<DriverRating>>(
            stream: DriverRatingRepository().passengerRatings(user.uid),
            builder: (context, ratingSnapshot) {
              final ratingsByBooking = {
                for (final rating
                    in ratingSnapshot.data ?? const <DriverRating>[])
                  rating.bookingId: rating,
              };
              return TripHistoryView(
                bookings: trips,
                itemBuilder: (context, booking) {
                  final submittedRating = ratingsByBooking[booking.bookingId];
                  return TripHistoryCard(
                    booking: booking,
                    otherPartyLabel: booking.driverName ?? 'Driver',
                    otherPartyPhotoUrl: booking.driverPhotoUrl,
                    submittedRating: submittedRating?.rating,
                    onTap: () => _openTripDetails(
                      context,
                      booking,
                      submittedRating,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _openTripDetails(
    BuildContext context,
    Booking booking,
    DriverRating? submittedRating,
  ) {
    final completed = booking.status == BookingStatus.completed;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (detailContext) => TripHistoryDetailScreen(
          booking: booking,
          driverView: false,
          submittedRating: submittedRating?.rating,
          onReceipt: completed
              ? () => Navigator.of(detailContext).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TripReceiptScreen(bookingId: booking.bookingId),
                  ),
                )
              : null,
          onRate: completed && submittedRating == null
              ? () => Navigator.of(detailContext).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RatingScreen(bookingId: booking.bookingId),
                  ),
                )
              : null,
          onReport: booking.driverId == null
              ? null
              : () => showRideReportDialog(
                  context: detailContext,
                  booking: booking,
                  reporterIsDriver: false,
                ),
        ),
      ),
    );
  }
}
