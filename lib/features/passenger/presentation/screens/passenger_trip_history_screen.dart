import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/booking.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/booking_repository.dart';
import '../../../../data/repositories/report_repository.dart';
import '../../../ride/tracking/widgets/expandable_trip_card.dart';
import '../../../ride/tracking/widgets/report_ride_dialog.dart';
import 'rating_screen.dart';
import 'trip_receipt_screen.dart';

class PassengerTripHistoryScreen extends ConsumerWidget {
  const PassengerTripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = AuthRepository().currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not signed in.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Trip History')),
      body: StreamBuilder<List<Booking>>(
        stream: BookingRepository().bookingsForPassenger(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
          final trips = snapshot.data ?? [];
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (trips.isEmpty) return const Center(child: Text('No trips yet.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final booking = trips[index];
              return ExpandableTripCard(
                booking: booking,
                otherPartyLabel: booking.driverName ?? 'Driver',
                onReceipt: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TripReceiptScreen(bookingId: booking.bookingId),
                )),
                onRate: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RatingScreen(bookingId: booking.bookingId),
                )),
                onReport: booking.driverId == null ? null : () => showDialog<void>(context: context, builder: (_) => ReportRideDialog(onSubmit: (category, details) => ReportRepository().create(bookingId: booking.bookingId, reporterId: user.uid, reportedUserId: booking.driverId!, category: category, details: details))),
              );
            },
          );
        },
      ),
    );
  }
}
