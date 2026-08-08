import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/core/maps/voltrike_map.dart';
import 'package:voltrike_v2/core/theme/app_semantic_colors.dart';
import 'package:voltrike_v2/core/theme/app_theme.dart';
import 'package:voltrike_v2/core/widgets/cards/app_card.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/tracking/screens/trip_history_detail_screen.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/trip_history_card.dart';
import 'package:voltrike_v2/features/ride/tracking/widgets/trip_history_view.dart';

void main() {
  testWidgets('history filters terminal trips and opens a full row', (
    tester,
  ) async {
    var openedBookingId = '';
    final completed = _booking(
      id: 'completed-trip',
      status: BookingStatus.completed,
      date: DateTime.now(),
    );
    final cancelled = _booking(
      id: 'cancelled-trip',
      status: BookingStatus.cancelled,
      date: DateTime.now().subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TripHistoryView(
            bookings: [completed, cancelled],
            itemBuilder: (context, booking) => TripHistoryCard(
              booking: booking,
              otherPartyLabel: booking.bookingId,
              onTap: () => openedBookingId = booking.bookingId,
            ),
          ),
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('completed-trip'), findsOneWidget);
    expect(find.text('cancelled-trip'), findsOneWidget);
    final historyCards = tester.widgetList<AppCard>(find.byType(AppCard));
    expect(
      historyCards.any(
        (card) => card.accentColor == AppSemanticColors.light.success,
      ),
      isTrue,
    );
    expect(
      historyCards.any(
        (card) => card.accentColor == AppTheme.lightTheme.colorScheme.error,
      ),
      isTrue,
    );

    await tester.tap(find.text('cancelled-trip'));
    expect(openedBookingId, 'cancelled-trip');

    await tester.tap(find.text('Cancelled').first);
    await tester.pumpAndSettle();

    expect(find.text('completed-trip'), findsNothing);
    expect(find.text('cancelled-trip'), findsOneWidget);
  });

  testWidgets('cancelled detail never exposes a completed receipt', (
    tester,
  ) async {
    final cancelled = _booking(
      id: 'cancelled-trip',
      status: BookingStatus.cancelled,
      date: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: TripHistoryDetailScreen(
          booking: cancelled,
          driverView: false,
          onReceipt: () {},
          onRate: () {},
          onReport: () {},
        ),
      ),
    );

    expect(find.text('Receipt'), findsNothing);
    expect(find.text('Rate driver'), findsNothing);
    expect(find.text('Report'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cancellation details'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cancellation details'), findsOneWidget);
  });
}

Booking _booking({
  required String id,
  required BookingStatus status,
  required DateTime date,
}) {
  return Booking(
    bookingId: id,
    passengerId: 'passenger',
    passengerName: 'Passenger',
    driverId: 'driver',
    driverName: 'Driver',
    vehicleNumber: 'E-Trike',
    plateNumber: 'AAA-1234',
    todaName: 'Barangay 40 TODA',
    pickup: const LatLng(10.67, 122.95),
    destination: const LatLng(10.68, 122.96),
    pickupAddress: 'Pickup address',
    destinationAddress: 'Destination address',
    distanceMeters: 3200,
    estimatedFare: 85,
    amountDue: 85,
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    status: status,
    createdAt: date.subtract(const Duration(minutes: 20)),
    updatedAt: date,
    completedAt: status == BookingStatus.completed ? date : null,
    cancelledAt: status == BookingStatus.cancelled ? date : null,
    cancelledBy: status == BookingStatus.cancelled ? 'passenger' : null,
    cancellationCode: status == BookingStatus.cancelled
        ? 'cancelled_by_passenger'
        : null,
  );
}
