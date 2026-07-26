import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/tracking/models/ride_action.dart';
import 'package:voltrike_v2/features/ride/tracking/services/ride_action_service.dart';

void main() {
  group('RideActionService', () {
    test('driver lifecycle actions follow booking order', () {
      expect(RideActionService.driverPrimaryAction(BookingStatus.driverAssigned), RidePrimaryAction.arriveAtPickup);
      expect(RideActionService.driverPrimaryAction(BookingStatus.driverArriving), RidePrimaryAction.startTrip);
      expect(RideActionService.driverPrimaryAction(BookingStatus.passengerOnBoard), RidePrimaryAction.dropOffPassenger);
      expect(RideActionService.driverPrimaryAction(BookingStatus.paymentConfirmation), RidePrimaryAction.completeTrip);
    });

    test('passenger cancellation is limited to pre-trip states', () {
      expect(RideActionService.passengerPrimaryAction(BookingStatus.pending), RidePrimaryAction.cancelRide);
      expect(RideActionService.passengerPrimaryAction(BookingStatus.driverAssigned), RidePrimaryAction.cancelRide);
      expect(RideActionService.passengerPrimaryAction(BookingStatus.passengerOnBoard), RidePrimaryAction.none);
    });

    test('only passengers receive a driver-rating action after completion', () {
      expect(
        RideActionService.passengerPrimaryAction(BookingStatus.completed),
        RidePrimaryAction.rateDriver,
      );
      expect(
        RideActionService.driverPrimaryAction(BookingStatus.completed),
        RidePrimaryAction.viewReceipt,
      );
    });

    test('terminal statuses do not expose a new ride lifecycle action', () {
      expect(
        RideActionService.driverPrimaryAction(BookingStatus.cancelled),
        RidePrimaryAction.none,
      );
      expect(
        RideActionService.passengerPrimaryAction(BookingStatus.cancelled),
        RidePrimaryAction.none,
      );
    });
  });
}
