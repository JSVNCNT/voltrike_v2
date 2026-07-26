import '../../../../data/models/booking.dart';

import '../models/ride_action.dart';
import '../models/ride_participant_role.dart';
import 'ride_stage_presentation_service.dart';

/// ===========================================================================
/// Ride Action Service
///
/// Maps a BookingStatus into the primary action shown in the UI.
///
/// This service contains ONLY business rules.
/// ===========================================================================
class RideActionService {
  const RideActionService._();

  //==========================================================================
  // Driver
  //==========================================================================

  static RidePrimaryAction driverPrimaryAction(
    BookingStatus status,
  ) => RideStagePresentationService.resolve(
    role: RideParticipantRole.driver,
    status: status,
  ).primaryAction;

  //==========================================================================
  // Passenger
  //==========================================================================

  static RidePrimaryAction passengerPrimaryAction(
    BookingStatus status,
  ) => RideStagePresentationService.resolve(
    role: RideParticipantRole.passenger,
    status: status,
  ).primaryAction;

  //==========================================================================
  // Helpers
  //==========================================================================

  static bool showPrimaryButton(
    RidePrimaryAction action,
  ) {
    return action != RidePrimaryAction.none;
  }
}
