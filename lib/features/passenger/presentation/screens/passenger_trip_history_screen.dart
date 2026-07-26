import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/models/driver_rating.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/driver_rating_repository.dart';
import '../../../../data/repositories/report_repository.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../ride/tracking/widgets/expandable_trip_card.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
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
  int _visibleCount = 10;

  @override
  Widget build(BuildContext context) {
    final user = AuthRepository().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Trip History')),
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
          final trips = snapshot.data ?? [];
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (trips.isEmpty) return const Center(child: Text('No trips yet.'));
          return StreamBuilder<List<DriverRating>>(
            stream: DriverRatingRepository().passengerRatings(user.uid),
            builder: (context, ratingSnapshot) {
              final ratingsByBooking = {
                for (final rating
                    in ratingSnapshot.data ?? const <DriverRating>[])
                  rating.bookingId: rating,
              };
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount:
                    (trips.length > _visibleCount
                        ? _visibleCount
                        : trips.length) +
                    (trips.length > _visibleCount ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == _visibleCount) {
                    return OutlinedButton(
                      onPressed: () => setState(() => _visibleCount += 10),
                      child: const Text('Load more trips'),
                    );
                  }
                  final booking = trips[index];
                  final submittedRating = ratingsByBooking[booking.bookingId];
                  return ExpandableTripCard(
                    booking: booking,
                    otherPartyLabel: booking.driverName ?? 'Driver',
                    otherPartyPhotoUrl: booking.driverPhotoUrl,
                    submittedRating: submittedRating?.rating,
                    onReceipt: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TripReceiptScreen(bookingId: booking.bookingId),
                      ),
                    ),
                    onRate: submittedRating != null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RatingScreen(bookingId: booking.bookingId),
                            ),
                          ),
                    onReport: booking.driverId == null
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => ReportRideDialog(
                              onSubmit: (category, details) =>
                                  ReportRepository().create(
                                    bookingId: booking.bookingId,
                                    reporterId: user.uid,
                                    reportedUserId: booking.driverId!,
                                    category: category,
                                    details: details,
                                  ),
                            ),
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
}
