import '../../../../data/models/booking.dart';
import '../models/ride_participant_role.dart';
import '../models/ride_status.dart';
import 'ride_stage_presentation_service.dart';

class RideStatusService {
  const RideStatusService._();

  static RideStatus driverStatus(
    BookingStatus status,
  ) => RideStagePresentationService.resolve(
    role: RideParticipantRole.driver,
    status: status,
  ).status;

  static RideStatus passengerStatus(
    BookingStatus status,
  ) => RideStagePresentationService.resolve(
    role: RideParticipantRole.passenger,
    status: status,
  ).status;
}
