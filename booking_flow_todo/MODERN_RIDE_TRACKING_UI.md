# Modern Ride Tracking UI

## Goal

Modernize the driver and passenger active-ride bottom sheets with Material 3
components while preserving VolTrike's existing teal color system, Poppins
typography, booking lifecycle, repositories, providers, routes, and callbacks.

## Non-negotiable behavior

- Do not add, rename, or persist any `BookingStatus`.
- `driverAssigned` is presented as "Driver matched" for passengers and
  "Heading to pickup" for drivers.
- Preserve the lifecycle:
  `pending -> driverAssigned -> driverArriving -> passengerOnBoard ->
  paymentConfirmation -> completed`, with existing cancellation paths.
- Preserve current Call, Chat, Report, SOS, Cancel, No-show, arrival, trip
  start, drop-off, cash confirmation, rating, and receipt handlers.
- Preserve live map markers, route polyline, ETA, warnings, and route target:
  pickup before trip start; destination after trip start.
- SOS currently records an incident for admin review and does not contact
  emergency services. Keep that disclosure in the confirmation flow.
- Do not show cash as confirmed until the booking is completed.

## Product decisions

- Keep VolTrike identity: existing teal seed color, Poppins, rounded surfaces,
  restrained elevation, and friendly plain-language copy.
- Use one compact participant summary rather than a large profile card.
- Use one canonical action area; remove duplicated passenger Call/Message UI.
- Keep the driver's primary lifecycle action sticky at the sheet bottom.
- Move external navigation from the sheet content to a small Material 3 map
  overlay button.
- Keep the existing Google Maps/Waze/system chooser behavior. A remembered
  local preference can be added separately without changing booking data.
- Use icon plus label for actions. The compact map navigation button may be
  icon-only but must have a tooltip and semantic label.

## State/action matrix

### Driver

- `driverAssigned`: Call, Chat, Report, SOS, Cancel; navigate to pickup;
  primary action "Arrived at Pickup".
- `driverArriving`: Call, Chat, Report, SOS, Cancel, No-show; navigate to
  pickup; primary action "Start Trip".
- `passengerOnBoard`: Call, Chat, Report, SOS; navigate to destination;
  primary action "Drop Off Passenger".
- `paymentConfirmation`: Report, SOS; primary action
  "Confirm Cash Received".

### Passenger

- `pending`: searching state with Cancel.
- `driverAssigned`: "Driver matched"; Call, Chat, Report, SOS, Cancel.
- `driverArriving`: "Driver at pickup"; Call, Chat, Report, SOS, Cancel.
- `passengerOnBoard`: Call, Chat, Report, SOS; no Cancel.
- `paymentConfirmation`: Report and SOS only.
- `completed`: rating/receipt flow.

## Implementation checklist

- [x] Add reusable compact participant and Material 3 action presentation.
- [x] Modernize shared ride action card without changing callbacks.
- [x] Modernize driver active tracking sheet.
- [x] Keep driver guidance inside the embedded Navigation SDK.
- [x] Modernize passenger active tracking sheet and remove duplicate actions.
- [x] Keep trip details available in the expanded sheet state.
- [x] Align "matched", pickup, onboard, and payment copy across both roles.
- [x] Add/update widget and policy tests for all state/action combinations.
- [x] Run Dart formatter.
- [x] Run targeted Flutter tests.
- [x] Run `flutter analyze`.

## Primary files

- `lib/features/driver/presentation/screens/driver_booking_tracking_screen.dart`
- `lib/features/passenger/presentation/screens/booking_tracking_screen.dart`
- `lib/features/ride/tracking/widgets/ride_actions_card.dart`
- `lib/features/ride/tracking/widgets/trip_status_card.dart`
- `lib/features/ride/tracking/widgets/trip_information_card.dart`
- `lib/features/ride/tracking/services/ride_stage_presentation_service.dart`
- `lib/features/driver/presentation/widgets/driver_turn_by_turn_map.dart`

## Token-saving resume strategy

When resuming after compaction:

1. Read this file first.
2. Inspect `git diff --` only for the primary files above.
3. Continue from the first unchecked checklist item.
4. Do not reread repositories or controllers unless a test proves the UI
   contract is unclear.
5. Use `RideStagePresentationService` as the action-visibility source of truth.
6. Reuse the existing screen callbacks; do not recreate backend operations.
7. Record important implementation decisions and completed verification below.

## Progress notes

- Context/TODO file created before implementation.
- Incoming driver offers now use one modern bottom card instead of duplicating
  the request at the top and in the old bottom sheet.
- Driver and passenger identity cards are compact, retain the existing data,
  and use the app's Material 3 color scheme and typography.
- The shared action card uses two-column Material 3 controls for Call, Chat,
  Report, SOS, Cancel, and No-show while forwarding the original callbacks.
- The passenger sheet no longer repeats Call and Chat in a second footer.
- Driver external navigation is a small accessible map overlay and still opens
  the existing Google Maps, Waze, or system chooser with the correct pickup or
  destination target.
- The driver's lifecycle button remains sticky and now reflects controller
  loading state.
- Targeted Dart analysis: no issues.
- Full `flutter analyze`: no issues (376.1 seconds).
- Focused ride lifecycle/action suite: 24 tests passed.
- Full Flutter test suite: 56 tests passed.
