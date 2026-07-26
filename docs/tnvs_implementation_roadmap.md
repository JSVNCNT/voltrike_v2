# VolTrike TNVS Implementation Roadmap

## Status and execution agreement

- This document is durable implementation context for the VolTrike TNVS work.
- No implementation begins until the user gives the go signal.
- Execute Milestones 1–5 first as the foundation.
- Continue with Milestones 6–11 after the foundation is implemented and checked.
- Do not use `flutter run` during Milestones 1–11.
- Non-launching checks such as formatting, static analysis, unit tests, repository/rules tests, Cloud Functions checks, and admin TypeScript compilation are allowed during implementation.
- Run the passenger app, driver app, and admin development server only in Milestone 12, after all implementation milestones are complete.
- Do not create a release build, configure release signing, package for an app store, deploy to production, or switch the project to production mode.
- Preserve existing Call, Chat, and Report implementations.
- Preserve current TODA, fare, coverage, and route-restriction behavior unless a milestone explicitly hardens its authorization or synchronization.
- IDs remain authoritative internal relationships. Names, photos, addresses, vehicle details, and other readable snapshots are used for user-facing display.

## Fixed search, distance, location, and dispatch requirements

### Pickup and destination search

- Keep the existing Google Places autocomplete and place-selection flow.
- Use the supplied Grab screenshot only as a UX reference for information
  hierarchy, not as a visual copy.
- Build the result list in VolTrike's identity: Poppins typography, teal
  `#008B8B`/dark-teal accents, white surfaces, existing spacing/radii, and
  VolTrike pickup/destination pin styling.
- Each result shows a readable place name, formatted street/locality address,
  dynamically measured proximity, and an optional entrance/sub-location when
  Google provides one.
- Do not reproduce Grab branding, GrabMaps, airport-only controls, scheduling
  controls, or other unrelated reference-app elements.
- Pickup-search distance is measured from the passenger's current location.
- Destination-search distance is measured from the selected pickup.
- If pickup has not yet been selected, destination search temporarily uses the passenger's current location.
- Only places within a strict 10 km radius of the applicable origin are eligible.
- A Places location bias alone is insufficient: the client must validate/filter the returned distance so a place beyond 10 km cannot be selected.
- Sort valid results by ascending distance.
- Mark the nearest valid result as `Recommended · Nearest`.
- Prefer autocomplete-provided `distanceMeters` when available so full place details do not have to be fetched for every row.
- Fetch and cache full place details only when a result is selected.
- Preserve the selected place ID internally, coordinates for routing, and readable place name/formatted address for display.

### Distance formatting

- The values below are formatter examples/test cases only. Search distances
  are never fixed or mocked: each result is measured dynamically from the
  applicable live GPS/search origin.
- Below 1,000 metres: round to a whole metre and display `m`.
- At or above 1,000 metres: display kilometres with one decimal place.
- Required examples:
  - `49.6` → `50 m`
  - `123` → `123 m`
  - `456` → `456 m`
  - `999` → `999 m`
  - `1000` → `1.0 km`
  - `1250` → `1.3 km`
  - `2100` → `2.1 km`
- Show the formatted distance as a visible badge/marker in each search result.
- Show route distance and duration after selection.

### Driver location and dispatch

- Nearby-driver discovery is backend/RTDB based and independent of Google Places.
- Driver location backend writes are throttled to at most once every 10 seconds.
- Local marker/navigation rendering may update more smoothly without increasing backend writes.
- Use RTDB `onDisconnect()` and server timestamps.
- Reject stale, inaccurate, offline, unavailable, unapproved, suspended, or otherwise ineligible drivers.
- Calculate driver-to-pickup distance using trusted backend location data.
- Only eligible drivers within 5 km of pickup may receive an offer.
- Rank eligible drivers nearest first and offer in controlled, expiring batches.
- Passengers see only the assigned driver's live marker once a driver is assigned.

## Administrator relationship and invariants

### Developer Admin

- Controls TODA registration approval/decline and TODA activation/suspension.
- Controls city fare configuration.
- Reviews TODA coverage requests.
- Controls developer-managed route restrictions.
- Can review all drivers and reports.
- Can suspend non-self user accounts.
- Can assign a TODA administrator.

### TODA Admin

- Belongs to exactly one TODA.
- Can see and manage only drivers assigned to that TODA.
- Can see and resolve only reports scoped to that TODA.
- Can submit coverage requests only for that TODA.
- Cannot change city fares.
- Cannot approve its own coverage request.
- Cannot manage developer route restrictions.
- Cannot suspend arbitrary passenger/user accounts.
- Must never gain Developer Admin permissions.

### Role and lifecycle safeguards

- Keep Firebase custom claims and `users/{uid}` role/`todaId` synchronized.
- Refresh ID tokens after role changes.
- Treat UI page visibility as presentation only; Cloud Functions and security rules remain the authorization boundary.
- Reject promotion of a driver to TODA Admin while that driver has an active ride.
- Ordinary driver, user, or TODA suspension must not strand or silently terminate an active ride.
- Suspending a TODA stops new bookings/offers immediately; active-ride handling must follow an explicit safe policy.
- Restoring a TODA must not automatically restore individually suspended drivers.
- Driver eligibility must check current user, driver, vehicle, license, and TODA status on the backend.
- Scope reports to the trusted booking/TODA relationship immediately where possible.
- Record sensitive administrative actions in an immutable audit trail.

## Milestone 1 — Canonical architecture and safe data parsing

- Establish one authoritative booking state machine.
- Add booking schema versioning.
- Make legacy documents safe to parse.
- Confirm unused legacy Trip/provider/service implementations before removal.
- Preserve admin, TODA, fare, coverage, and route behavior.
- Add shared formatting utilities, including exact distance formatting.
- Add tests for all required metres/kilometres boundary cases.

## Milestone 2 — Atomic backend booking lifecycle

Implement backend-authoritative, idempotent operations for:

- Booking creation.
- Driver acceptance.
- Driver arrival.
- Pickup confirmation.
- Trip start.
- Trip completion.
- Passenger cancellation.
- Driver cancellation.
- No-show.

Atomically synchronize:

- Booking status and lifecycle timestamps.
- Driver availability and `currentBookingId`.
- Offer status and cleanup.
- Cancellation/no-show metadata.
- Completion state and applicable statistics/settlement hooks.
- Immutable audit events.

Required guarantees:

- Passenger cancellation releases an assigned driver.
- Completion/cancellation cannot split booking and driver state.
- Duplicate requests are harmless.
- Two drivers cannot accept the same booking.
- Restart recovery reads the same durable state on both apps.

## Milestone 3 — Administrator relationship hardening

- Preserve all existing Developer Admin/TODA Admin role boundaries.
- Add custom-claim/profile consistency checks.
- Add token-refresh handling after role changes.
- Protect active rides before driver suspension, TODA suspension, user suspension, or admin promotion.
- Implement safe TODA suspension behavior.
- Require explicit individual driver restoration.
- Validate TODA and complete driver eligibility on the backend.
- Scope reports immediately from trusted booking data.
- Add audit records for sensitive admin actions.
- Ensure no TODA Admin gains Developer Admin capabilities.

## Milestone 4 — Pickup and destination search within 10 km

- Keep Google Places autocomplete and selection.
- Add input debouncing and Places session tokens.
- Set the correct distance origin for pickup versus destination.
- Request distance data without fetching full details for every row where supported.
- Strictly exclude results beyond 10 km.
- Sort valid results nearest first.
- Mark the nearest result as recommended.
- Use the exact shared metre/kilometre formatter.
- Fetch and cache full details only on selection.
- Preserve readable name, address, place ID, and coordinates.
- Show pickup and destination markers plus route distance/duration.
- Avoid repeated reverse-geocoding and duplicate API requests.

## Milestone 5 — Five-kilometre backend driver discovery

- Keep nearby-driver discovery independent from Google Places.
- Store driver coordinates in RTDB.
- Throttle backend location writes to once every 10 seconds.
- Configure RTDB `onDisconnect()`.
- Validate server timestamps, freshness, and accuracy.
- Calculate driver-to-pickup distance on the trusted backend.
- Include only eligible drivers within 5 km.
- Rank nearest drivers first.
- Offer rides in controlled batches.
- Expire and clean offers after timeout, acceptance, or cancellation.
- Show assigned-driver distance and ETA to the passenger.
- Smooth marker movement between 10-second backend updates.
- Restrict location visibility to the appropriate assigned passenger and authorized operational roles where feasible.

## Milestone 6 — Backend fare and route validation

- Preserve Developer Admin fare control.
- Keep TODA Admin unable to modify city fares.
- Store a versioned fare-configuration snapshot on the booking.
- Validate route distance and fare using trusted backend logic.
- Preserve current route-restriction behavior.
- Prevent modified clients from submitting arbitrary fare/distance data.
- Reduce duplicate Google API calls.
- Remove verbose Places request/response logging.
- Add controlled network timeouts, retry behavior, and recoverable errors.

## Milestone 7 — Complete ride UI

- Show passenger name and photo on incoming driver offers.
- Show readable pickup/destination, fare, distance, timer, Accept, and Decline.
- Show driver name, photo, rating, vehicle, plate, and TODA to the passenger.
- Show driver-to-pickup distance and remaining-trip distance.
- Add the existing birthdate value to passenger and driver profiles.
- Use safe missing-image and missing-data fallbacks.
- Never display a UID as a normal user identity.
- Preserve readable counterpart information in completed and cancelled history.
- Avoid per-row/N+1 profile reads by using booking snapshots and existing providers.

## Milestone 8 — Call, chat, report, and pickup confirmation

- Preserve existing Call, Chat, and Report implementations.
- Verify correct booking and participant IDs throughout the lifecycle.
- Make action availability consistent with applicable booking states.
- Add passenger pickup PIN/confirmation before the trip can enter the onboard state.
- Keep reporting available after completion where currently supported.
- Validate chat members from the booking instead of trusting a client-supplied list.
- Preserve LiveKit server-secret and short-lived-token handling.

## Milestone 9 — TNVS safety foundation

- Add an SOS action.
- Add emergency-contact data.
- Add share-trip information.
- Add structured cancellation reasons.
- Add passenger/driver no-show handling.
- Add safety incidents with booking and location snapshots.
- Enforce driver license and vehicle validity.
- Ensure safe driver/user/TODA suspension behavior.
- Add admin safety-incident visibility.
- Keep external emergency-service integrations as development-only placeholders.

## Milestone 10 — Cash settlement, ratings, and earnings

- Add an explicit cash payment method.
- Record amount due.
- Record passenger-paid and driver-received confirmation.
- Add settlement timestamp and receipt/reference number.
- Add adjustment/dispute state.
- Aggregate driver ratings on the backend.
- Aggregate completed trips and earnings on the backend.
- Make completion/accounting idempotent so retries never duplicate earnings.

## Milestone 11 — Admin operational improvements

- Maintain current Developer Admin and TODA Admin pages and permissions.
- Add pagination.
- Reduce N+1 profile reads.
- Add booking-lifecycle lookup.
- Add search by readable name, booking reference, driver, passenger, and plate.
- Add report and safety history.
- Add settlement visibility.
- Add role-scope authorization tests.
- Add an immutable audit trail.
- Preserve privacy restrictions for TODA Admins outside their authorized TODA.

## Milestone 12 — Final verification after all implementation

Do not begin this milestone until Milestones 1–11 are implemented.

Allowed final development execution:

- Run the passenger application using `flutter run`.
- Run the driver application using `flutter run`.
- Run the admin development server.
- Perform a full two-device lifecycle test.

Final lifecycle coverage:

- Pickup/destination search and exact distance display.
- Booking creation and fare snapshot.
- Five-kilometre backend dispatch.
- Driver acceptance race protection.
- Passenger and driver tracking.
- Arrival and pickup confirmation.
- Call, Chat, and Report.
- Cancellation and no-show.
- App termination and restart recovery.
- Trip start and completion.
- Cash settlement.
- Rating and earnings aggregation.
- Receipt and history.
- Passenger and driver profiles.
- SOS/safety records.
- Developer Admin and TODA Admin synchronization and scope.

Explicit exclusions:

- No release build.
- No release signing.
- No app-store packaging.
- No production deployment.
- No production-mode switch.
