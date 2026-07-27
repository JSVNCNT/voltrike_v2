import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/tracking/models/ride_participant_role.dart';
import 'package:voltrike_v2/features/ride/tracking/services/ride_stage_presentation_service.dart';

void main() {
  group('tracking action matrix', () {
    for (final role in RideParticipantRole.values) {
      test('${role.name} searching exposes only cancellation', () {
        final stage = RideStagePresentationService.resolve(
          role: role,
          status: BookingStatus.pending,
        );

        expect(stage.allowContact, isFalse);
        expect(stage.allowReport, isFalse);
        expect(stage.allowSos, isFalse);
        expect(stage.allowCancel, role == RideParticipantRole.passenger);
      });

      for (final status in const [
        BookingStatus.driverAssigned,
        BookingStatus.driverArriving,
      ]) {
        test('${role.name} ${status.name} exposes pickup coordination', () {
          final stage = RideStagePresentationService.resolve(
            role: role,
            status: status,
          );

          expect(stage.allowContact, isTrue);
          expect(stage.allowCancel, isTrue);
          expect(stage.allowReport, isTrue);
          expect(stage.allowSos, isTrue);
        });
      }

      test('${role.name} in-progress exposes contact and safety actions', () {
        final stage = RideStagePresentationService.resolve(
          role: role,
          status: BookingStatus.passengerOnBoard,
        );

        expect(stage.allowContact, isTrue);
        expect(stage.allowCancel, isFalse);
        expect(stage.allowReport, isTrue);
        expect(stage.allowSos, isTrue);
      });

      test('${role.name} completed exposes no tracking actions', () {
        final stage = RideStagePresentationService.resolve(
          role: role,
          status: BookingStatus.completed,
        );

        expect(stage.allowContact, isFalse);
        expect(stage.allowCancel, isFalse);
        expect(stage.allowReport, isFalse);
        expect(stage.allowSos, isFalse);
        expect(stage.allowNoShow, isFalse);
      });

      test('${role.name} payment confirmation still permits reporting', () {
        final stage = RideStagePresentationService.resolve(
          role: role,
          status: BookingStatus.paymentConfirmation,
        );
        expect(stage.allowContact, isFalse);
        expect(stage.allowCancel, isFalse);
        expect(stage.allowReport, isTrue);
        expect(stage.allowSos, isTrue);
      });
    }

    test('driver no-show remains pickup-only', () {
      expect(
        RideStagePresentationService.resolve(
          role: RideParticipantRole.driver,
          status: BookingStatus.driverArriving,
        ).allowNoShow,
        isTrue,
      );
      expect(
        RideStagePresentationService.resolve(
          role: RideParticipantRole.driver,
          status: BookingStatus.passengerOnBoard,
        ).allowNoShow,
        isFalse,
      );
    });

    test('matched and navigation copy stay presentation-only', () {
      final passengerMatched = RideStagePresentationService.resolve(
        role: RideParticipantRole.passenger,
        status: BookingStatus.driverAssigned,
      );
      final driverPickup = RideStagePresentationService.resolve(
        role: RideParticipantRole.driver,
        status: BookingStatus.driverAssigned,
      );
      final driverDestination = RideStagePresentationService.resolve(
        role: RideParticipantRole.driver,
        status: BookingStatus.passengerOnBoard,
      );

      expect(passengerMatched.status.title, 'Driver Matched');
      expect(driverPickup.status.title, 'Heading to Pickup');
      expect(driverDestination.status.title, 'Heading to Destination');
    });
  });
}
