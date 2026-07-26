# BOOKING FLOW DONE

## RULES
- Move only fully implemented milestones here.
- Record actual verification; never inferred verification.
- Keep entries telegraphic.

## ENTRY FORMAT
### MXX [x] Milestone
- RESULT:
- CHANGED:
- FILES:
- VERIFIED:
- DEPLOYED:
- REMAINS:

## COMPLETED

### B00 [x] Stage-specific tracking actions
- RESULT: Shared passenger/driver action matrix implemented.
- CHANGED: Pickup Call/Chat/Cancel; in-trip Report/SOS; terminal none.
- FILES: `ride_stage_presentation_service.dart`; matrix test.
- VERIFIED: 11 focused Flutter tests passed.
- DEPLOYED: No.
- REMAINS: Driver No-show intentionally remains pickup-only.

### M01 [x] Durable payment-confirmation lifecycle
- RESULT: Durable intermediate booking status implemented.
- CHANGED: Drop-off and completion are separate driver-only transitions.
- FILES: Flutter booking model/state machine; Functions lifecycle; routing.
- VERIFIED: Source implementation only; runtime deferred by instruction.
- DEPLOYED: No.
- REMAINS: M09 verification and deployment.

### M02 [x] Confirmed driver cash drop-off
- RESULT: Drop-off and cash-received confirmations implemented.
- CHANGED: Duplicate action guard; atomic completion remains server-side.
- FILES: Driver controller/tracking/home; booking callable.
- VERIFIED: Source implementation only; runtime deferred by instruction.
- DEPLOYED: No.
- REMAINS: Repeated-tap and two-role runtime verification.

### M03 [x] Rating, skip, and receipt finalization
- RESULT: Skip, duplicate detection, and receipt routing implemented.
- CHANGED: Existing ratings bypass rating and hide repeated action.
- FILES: Rating screen; receipt screen; rating repository.
- VERIFIED: Source implementation only; runtime deferred by instruction.
- DEPLOYED: No.
- REMAINS: Offline and restoration runtime verification.

### M04 [x] Clean passenger Return Home
- RESULT: Completion-only temporary passenger state reset implemented.
- CHANGED: History receipts preserve any current booking work.
- FILES: Receipt screen; passenger state providers.
- VERIFIED: Source implementation only; runtime deferred by instruction.
- DEPLOYED: No.
- REMAINS: Widget verification.

### M05 [x] Searching-for-driver map
- RESULT: Pickup, destination, route, overlay, and cancel guard implemented.
- CHANGED: Google route with straight-line failure fallback.
- FILES: Searching driver screen.
- VERIFIED: Source implementation only; visual checks deferred.
- DEPLOYED: No.
- REMAINS: Phone-size and API runtime verification.

### M06 [x] Server-persisted driver decline
- RESULT: Decline callable persists offer and redispatches immediately.
- CHANGED: Declined drivers excluded from later offer rounds.
- FILES: Functions dispatch; booking repository; driver controller.
- VERIFIED: Source implementation only; concurrency tests deferred.
- DEPLOYED: No.
- REMAINS: Functions deployment and concurrency verification.

### M07 [x] Live admin booking operations
- RESULT: Metrics, reports, bookings, settlements refresh every five seconds.
- CHANGED: Polling cleanup added on component unmount.
- FILES: Admin App.
- VERIFIED: Source implementation only; typecheck deferred.
- DEPLOYED: No.
- REMAINS: Browser and role-scope smoke verification.

### M08 [x] Lifecycle copy and recovery polish
- RESULT: Arrival/cancellation copy and driver receipt recovery implemented.
- CHANGED: Pending driver receipt survives restart until acknowledged.
- FILES: Functions notifications; driver repository/home; receipt screen.
- VERIFIED: Source implementation only; restart test deferred.
- DEPLOYED: No.
- REMAINS: Legacy-data and restart runtime verification.
