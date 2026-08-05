import '../../../app/routes.dart';
import '../../../data/models/booking.dart';

enum BookingParticipantRole { passenger, driver }

class BookingRouteDecision {
  const BookingRouteDecision({required this.location, this.bookingId});

  final String location;
  final String? bookingId;

  bool get carriesBooking => bookingId != null && bookingId!.isNotEmpty;
}

class BookingRouteResolver {
  const BookingRouteResolver._();

  static BookingRouteDecision resolve({
    required BookingParticipantRole role,
    required BookingStatus status,
    required String bookingId,
  }) {
    return switch ((role, status)) {
      (BookingParticipantRole.passenger, BookingStatus.pending) =>
        BookingRouteDecision(
          location: AppRoutes.withBookingId(
            AppRoutes.searchingDriver,
            bookingId,
          ),
          bookingId: bookingId,
        ),
      (
        BookingParticipantRole.passenger,
        BookingStatus.driverAssigned ||
            BookingStatus.driverArriving ||
            BookingStatus.passengerOnBoard ||
            BookingStatus.paymentConfirmation,
      ) =>
        BookingRouteDecision(
          location: AppRoutes.withBookingId(
            AppRoutes.driverTracking,
            bookingId,
          ),
          bookingId: bookingId,
        ),
      (BookingParticipantRole.passenger, BookingStatus.completed) =>
        BookingRouteDecision(
          location: AppRoutes.withBookingId(AppRoutes.rateDriver, bookingId),
          bookingId: bookingId,
        ),
      (BookingParticipantRole.passenger, BookingStatus.cancelled) =>
        const BookingRouteDecision(location: AppRoutes.passengerHome),
      (
        BookingParticipantRole.driver,
        BookingStatus.driverAssigned ||
            BookingStatus.driverArriving ||
            BookingStatus.passengerOnBoard ||
            BookingStatus.paymentConfirmation,
      ) =>
        BookingRouteDecision(
          location: AppRoutes.withBookingId(
            AppRoutes.driverBookingTracking,
            bookingId,
          ),
          bookingId: bookingId,
        ),
      (
        BookingParticipantRole.driver,
        BookingStatus.pending ||
            BookingStatus.completed ||
            BookingStatus.cancelled,
      ) =>
        const BookingRouteDecision(location: AppRoutes.driverHome),
    };
  }
}
