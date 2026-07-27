import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/tracking/services/ride_status_service.dart';

void main() {
  group('RideStatusService', () {
    test('uses role-appropriate assigned and active-trip labels', () {
      expect(
        RideStatusService.passengerStatus(BookingStatus.driverAssigned).title,
        'Driver Matched',
      );
      expect(
        RideStatusService.driverStatus(BookingStatus.driverAssigned).title,
        'Heading to Pickup',
      );
      expect(
        RideStatusService.passengerStatus(BookingStatus.passengerOnBoard).title,
        'Trip in Progress',
      );
      expect(
        RideStatusService.driverStatus(BookingStatus.passengerOnBoard).title,
        'Heading to Destination',
      );
    });

    test('uses terminal labels for cancelled and completed rides', () {
      expect(
        RideStatusService.passengerStatus(BookingStatus.cancelled).title,
        'Ride Cancelled',
      );
      expect(
        RideStatusService.driverStatus(BookingStatus.completed).title,
        'Trip Completed',
      );
    });
  });
}
