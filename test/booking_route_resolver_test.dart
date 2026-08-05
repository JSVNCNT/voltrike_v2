import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/app/routes.dart';
import 'package:voltrike_v2/data/models/booking.dart';
import 'package:voltrike_v2/features/ride/routing/booking_route_resolver.dart';

void main() {
  const bookingId = 'booking-123';

  group('BookingRouteResolver passenger recovery', () {
    test('restores pending booking to driver search', () {
      final decision = BookingRouteResolver.resolve(
        role: BookingParticipantRole.passenger,
        status: BookingStatus.pending,
        bookingId: bookingId,
      );

      expect(
        decision.location,
        AppRoutes.withBookingId(AppRoutes.searchingDriver, bookingId),
      );
      expect(decision.bookingId, bookingId);
    });

    test('restores every active ride status to tracking', () {
      for (final status in const [
        BookingStatus.driverAssigned,
        BookingStatus.driverArriving,
        BookingStatus.passengerOnBoard,
        BookingStatus.paymentConfirmation,
      ]) {
        final decision = BookingRouteResolver.resolve(
          role: BookingParticipantRole.passenger,
          status: status,
          bookingId: bookingId,
        );

        expect(
          decision.location,
          AppRoutes.withBookingId(AppRoutes.driverTracking, bookingId),
        );
        expect(decision.bookingId, bookingId);
      }
    });

    test('routes terminal statuses to rating or home', () {
      final completed = BookingRouteResolver.resolve(
        role: BookingParticipantRole.passenger,
        status: BookingStatus.completed,
        bookingId: bookingId,
      );
      final cancelled = BookingRouteResolver.resolve(
        role: BookingParticipantRole.passenger,
        status: BookingStatus.cancelled,
        bookingId: bookingId,
      );

      expect(
        completed.location,
        AppRoutes.withBookingId(AppRoutes.rateDriver, bookingId),
      );
      expect(completed.bookingId, bookingId);
      expect(cancelled.location, AppRoutes.passengerHome);
      expect(cancelled.carriesBooking, isFalse);
    });
  });

  group('BookingRouteResolver driver recovery', () {
    test('restores every accepted ride status to tracking', () {
      for (final status in const [
        BookingStatus.driverAssigned,
        BookingStatus.driverArriving,
        BookingStatus.passengerOnBoard,
        BookingStatus.paymentConfirmation,
      ]) {
        final decision = BookingRouteResolver.resolve(
          role: BookingParticipantRole.driver,
          status: status,
          bookingId: bookingId,
        );

        expect(
          decision.location,
          AppRoutes.withBookingId(AppRoutes.driverBookingTracking, bookingId),
        );
        expect(decision.bookingId, bookingId);
      }
    });

    test('routes non-active statuses to driver home', () {
      for (final status in const [
        BookingStatus.pending,
        BookingStatus.completed,
        BookingStatus.cancelled,
      ]) {
        final decision = BookingRouteResolver.resolve(
          role: BookingParticipantRole.driver,
          status: status,
          bookingId: bookingId,
        );

        expect(decision.location, AppRoutes.driverHome);
        expect(decision.carriesBooking, isFalse);
      }
    });
  });
}
