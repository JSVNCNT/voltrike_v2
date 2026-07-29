# VolTrike Mobile App-Wide Dark Mode DONE

Status: implemented and passing automated validation.

## Scope delivered

- Added Dark mode to the signed-in Flutter mobile app for both passenger and
  driver experiences.
- Added one shared toggle at Profile -> Settings -> Appearance.
- Kept `admin/` completely out of scope.
- Kept splash, introduction, authentication, email verification, account
  suspension, passenger registration, driver registration/upload/review, and
  under-review content visually Light.
- Kept registration Privacy/Terms acknowledgements Light while allowing the
  same legal screens opened from signed-in Settings to follow the selected
  theme.
- Did not change booking, Firebase, account, or admin business data.

## Theme state and persistence

- Added `shared_preferences` and a device-local versioned preference:
  `voltrike.dark_mode.v1`.
- Light remains the safe default when the preference is absent or cannot be
  loaded.
- The preference loads before `runApp`, preventing a signed-in Light flash.
- Riverpod owns one shared Light/Dark state for passenger and driver sessions.
- The Settings switch changes the app immediately and persists across restart,
  logout, and later login.
- A failed preference write rolls the visible mode back and shows a readable
  snackbar instead of leaving UI and storage out of sync.

## Design and readability improvements

- Replaced the old copied Light theme with complete explicit Light and Dark
  `ColorScheme`s.
- Preserved VolTrike's teal identity, Poppins typography, rounded cards, calm
  spacing, and green/amber/red ride meanings.
- Uses deep teal-charcoal backgrounds and layered teal surfaces instead of pure
  black, with brighter accessible teal accents in Dark mode.
- Added paired semantic roles for success, warning, information, rating, call,
  chat, report, and safety actions.
- Added complete themed app bars, fields, selections, buttons, switches,
  cards, navigation bars, dialogs, sheets, chips, segmented controls,
  dividers, snackbars, indicators, tooltips, disabled states, and system bars.
- Removed light-only neutral colors from shared cards, fields, dialogs,
  loading/empty states, profile widgets, dashboards, chat, trip history,
  tracking, rating, place results, and ride actions.
- About VolTrike now selects the logo variant appropriate for the active
  surface.
- Call screens remain intentionally immersive Dark and now force Light system
  icons in either app mode.

## Screen and interaction improvements

- Passenger and driver Settings share the same accessible 68-pixel Dark mode
  switch row.
- Passenger/driver dashboards and profiles use theme-aware success, warning,
  error, rating, online/offline, approval, licence, and earnings accents.
- Dashboard metric cards no longer force a 116-pixel height or shrink text with
  `FittedBox`; labels and values may occupy two readable lines.
- Place results use paired container colors for icons, recommendations, and
  distance badges.
- Searching-for-driver status colors now use accessible semantic foreground
  and container pairs. The map overlay can scroll on a short screen or with
  enlarged text.
- Driver booking restrictions and navigation instructions use error and
  secondary container pairs instead of Light-only red/teal panels.
- Chat composer, borders, incoming/outgoing bubbles, timestamps, empty state,
  and send controls now follow the active scheme.
- Trip history cards/details use themed avatars, route connectors, status,
  rating, text, and bottom actions.
- Trip history filters scroll horizontally rather than clipping at narrow
  widths or large text.
- Ride quick actions use semantic foreground/background pairs and guarantee a
  minimum 48-pixel target.
- Ride action buttons may grow vertically when labels wrap.
- The confirmation slider supports two-line labels and has a readable disabled
  foreground.
- Rating stars can wrap instead of overflowing narrow displays.
- Dialogs, snackbars, loading overlays, destructive logout actions, and shared
  form components now use paired theme colors.

## Map and navigation improvements

- The app-owned Google map wrapper sets an initial Light/Dark map scheme,
  preventing a bright native map flash.
- A live Settings change calls `setMapColorScheme` without discarding markers
  or route overlays.
- Native driver turn-by-turn navigation starts in forced day/night mode to
  match the selected app mode and updates while guidance remains mounted.
- Existing route and marker identity remains intact.

## Searching-driver radar and timeout redesign

- Replaced the previous centered search card with three animated, translucent
  orange radar rings like the supplied reference.
- The radar is centered on the pickup camera while the destination marker and
  requested route remain visible.
- Added a rounded bottom sheet with `Looking for a driver`, capacity-aware
  supporting copy, a live `1:00` countdown, progress, and a full-width red
  `Cancel request` button.
- The countdown is derived from the booking creation time rather than screen
  lifetime, so reopening the screen cannot reset it.
- After 60 seconds, a still-pending request is cancelled and its outstanding
  offers are closed.
- The backend timeout policy accepts `search_timeout` only from `pending`.
  A driver assignment that wins the race proceeds normally and cannot be
  cancelled by the timer.
- The terminal sheet always says `No drivers available`, then explains one of:
  - no high-capacity electric tuktuks are available;
  - no tuktuks are serving the area;
  - no nearby drivers are currently available.
- Temporary connectivity failures keep the passenger on the screen, explain
  that VolTrike is retrying, and offer an immediate retry action.
- Added `Back to home` after a confirmed timeout.

## Authentication boundary

- Added a reusable fixed-Light theme and system-overlay boundary.
- Applied it at the router level instead of editing authentication or
  registration screen implementations.
- Auth and registration routes therefore stay Light even if a previous
  signed-in session saved Dark mode.
- No file under `admin/` and no authentication/registration screen source was
  edited.

## Automated validation

- `dart format`: completed for every changed Dart and test file.
- `flutter analyze`: passed with no issues.
- `flutter test --no-pub`: all 93 tests passed.
- `functions/npm.cmd test`: all 24 backend tests passed.
- `git diff --check`: passed; only repository line-ending notices were shown.
- Added tests for:
  - safe Light default;
  - Dark persistence;
  - failed-write rollback;
  - complete Light/Dark theme construction;
  - semantic theme installation;
  - critical Dark contrast pairs;
  - immediate Settings toggle/repaint;
  - fixed-Light public content.
  - search countdown anchoring and formatting;
  - high-capacity and service-area availability messages;
  - pending-only backend timeout cancellation.
- Existing ride quick-action, narrow identity-card, trip history, slider,
  shell, auth, registration, routing, model, and service tests remain passing.

## Intentionally not claimed as automated

- Native Google map/night-navigation rendering still needs a real Android
  platform-view smoke test because Flutter widget tests cannot render the
  Google native view.
- A final human visual pass across representative 320x568 and 430x932 devices,
  text scales 1.0/1.5/2.0, keyboards, and live ride states remains listed in
  `todo.md`.
- Dormant duplicate/legacy ride widgets were not migrated or deleted because
  they are not reachable and dead-code cleanup was outside this feature.

## Key implementation files

- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_semantic_colors.dart`
- `lib/core/theme/theme_preference_store.dart`
- `lib/core/providers/theme_provider.dart`
- `lib/core/theme/fixed_light_theme.dart`
- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/features/common/presentation/widgets/settings_view.dart`
- `lib/core/maps/voltrike_map.dart`
- `lib/features/driver/presentation/widgets/driver_turn_by_turn_map.dart`
- `test/app_theme_test.dart`

## TODA zone-aware booking pre-implementation baseline (historical)

Status: analysis completed on 2026-07-29. No zone-aware implementation is
claimed in this baseline section. Every behavior described below is the state
that was found before the implementation recorded in the next section.

### Verified repository facts

- No repository `AGENTS.md` file was found, so there are no additional
  repository-local agent instructions beyond the existing project documents.
- The machine has the stable `x86_64-pc-windows-msvc` Rust toolchain with
  `rustc 1.94.0` and `cargo 1.94.0`.
- The repository has no `Cargo.toml`, `.rs` source, Flutter Rust Bridge,
  `dart:ffi` Rust binding, N-API addon, or application-owned WebAssembly
  bridge. The generated `jni` plugin entries belong to existing Flutter
  dependencies and are not a VolTrike Rust integration.
- No Rust update was needed or performed. An app-wide language/runtime
  migration is intentionally outside this feature because Firebase network
  latency, Google route requests, and transactional correctness dominate this
  workflow; replacing UI and Firebase adapters would expand risk without
  fixing the current policy gaps.
- Flutter is currently the mobile UI and client orchestration layer. It calls
  callable Firebase Functions for authoritative booking mutations.
- `admin/` is a React 18/TypeScript/Vite application. It uses direct,
  rule-protected Firestore reads and callable Functions for privileged writes.
- `functions/` is a Node 22 CommonJS Firebase Functions codebase. Booking,
  admin, fare, notification, and safety I/O live in `index.js`, with small pure
  JavaScript policy modules and Node tests beside it.

### Verified current coverage and restriction behavior

- A TODA admin can draw and submit coverage only for its claimed TODA. A
  developer admin can select a TODA, submit a request, edit pending request
  geometry, and approve or decline it.
- Approval attempts to copy the reviewed request to
  `geofences/{todaId}`. The current functions persist polygons as nested
  numeric arrays (`[[longitude, latitude], ...]`) and MultiPolygons as a
  further nested array. This is not a valid durable Firestore array shape and
  is a concrete schema defect consistent with the reported generic
  `functions/internal` failure. Production Function logs were not available
  in this audit, so the exact deployed exception is not claimed.
- The same nested-array persistence defect exists in route-restriction writes.
- Coverage validation currently checks only array sizes and finite numbers. It
  does not enforce coordinate ranges, self-intersection, minimum area,
  revision ordering, overlap policy, or reviewed-state transitions.
- An approved geofence is not currently read by booking creation, fare
  calculation, or driver dispatch. It therefore does not yet decide who may
  serve a pickup.
- Active route restrictions are read by Flutter and cached for five minutes.
  The client requests Google alternatives and rejects alternatives that
  conflict with a configured polygon or corridor.
- The authoritative backend route lookup does not read route restrictions and
  does not request a route polyline. Native driver Navigation SDK guidance may
  also independently reroute through a restriction. Current behavior is a
  client warning/route-selection aid, not end-to-end enforcement.
- Corridor conflict checking samples decoded route points near the centreline;
  it does not calculate full route-segment-to-corridor-segment distance.

### Verified current booking, dispatch, and fare behavior

- The backend searches approved, online, available drivers with fresh
  accurate RTDB locations, filters to a hard-coded five-kilometre radius,
  rechecks user/TODA/vehicle/licence/capacity eligibility, sorts by straight
  line distance, and offers the nearest five from the first 100 queried driver
  documents.
- Dispatch does not currently filter candidates by coverage or TODA. The
  booking has `todaId: null` until a driver accepts, after which the accepting
  driver's TODA is copied onto the booking.
- All drivers in an offered batch may press Accept. The first valid
  `acceptBookingLifecycle` Firestore transaction to commit assigns the
  booking and reserves the driver; later contenders fail because the booking
  is no longer pending. This prevents double assignment but does not guarantee
  that the nearest offered driver wins.
- The passenger search timeout is 60 seconds while backend offers live for 120
  seconds and scheduled redispatch runs once per minute. A normal 60-second
  timeout therefore ends before the next 120-second offer round.
- Declining one offer forces immediate redispatch, but the current batch logic
  marks every previously offered driver's offer expired, including peers who
  had not declined.
- The authoritative fare formula is base fare plus each started distance step
  beyond the included metres, per-additional-passenger fee, baggage fee, and
  one outside-TODA surcharge. The developer admin owns one versioned city fare
  document.
- Backend booking creation recalculates distance and total fare, but trusts the
  client `isOutsideToda` Boolean. The normal mobile booking session never
  derives that flag from an approved geofence and defaults it to `false`.
- Flutter reads the legacy key `outOfBarangayFee` while the admin/backend store
  `outsideTodaSurcharge`; consequently the mobile boundary-fee preview falls
  back to zero even when the admin value exists.
- The backend stores the fare configuration snapshot and total, while the
  detailed line-item preview is calculated only in Flutter.

### Assets and audit scope

- `assets/icons/warning.png` exists, is registered through `assets/icons/`,
  and is a transparent 2100x2100 ARGB PNG of about 1.1 MB. Existing driver
  restriction panels already use `Icons.warning_amber_rounded`, which is the
  lighter option for a small navigation warning.
- Files reviewed include the coverage/restriction admin pages and callable
  API, Firestore rules/indexes, booking lifecycle and dispatch Functions,
  fare policy/repositories, mobile booking session, route-restriction and
  route services, driver navigation, emulator seed/verification, and related
  tests.
- The initial audit phase changed only the appended planning/analysis sections in
  `todo.md` and `done.md`. It did not edit application code, dependencies,
  generated files, Firebase configuration, or the Rust toolchain.

## TODA coverage, booking award, fare, and restriction implementation

Status: scoped implementation completed and locally verified on 2026-07-29.
No Firebase deployment or production data mutation was performed.

### Coverage requests and the reported internal error

- The concrete Firestore defect was removed. Coverage and restriction writes
  now use geometry version 2:
  `areas: [{points: [{latitude, longitude}]}]`. An array contains maps rather
  than another array, so the previous nested-array write that was consistent
  with `functions/internal` is no longer generated.
- Legacy `[longitude, latitude]` tuples remain readable at JavaScript,
  TypeScript, and Dart adapters, but every new server write uses named
  coordinates. Values are checked for finite/ranged coordinates, point and
  area limits, unique/non-degenerate points, minimum polygon area, and
  self-intersection.
- A TODA administrator can submit and revise only its own pending request. A
  developer administrator can create for a selected TODA, edit a pending
  request, approve, or decline it. Review buttons are disabled while that
  request has unsaved map edits.
- Edit/review state checks now run in Firestore transactions. Approval
  revalidates that the TODA is active and atomically writes the reviewed
  request, active `geofences/{todaId}` record, monotonically increasing
  `coverageRevision`, and audit entry. A v2 request older than the currently
  active source request cannot replace it.
- Admin readers display geometry version, area/point counts, and coordinate
  bounds. Safe callable validation messages replace the otherwise generic
  internal-error copy, while rejected geometry is logged with actor,
  request, and TODA identifiers where available.

### Booking coverage and fare policy

- Booking creation now loads active approved geofences on the backend and
  classifies both endpoints. The client-provided `isOutsideToda` value is
  retained only as a diagnostic estimate and cannot decide jurisdiction or
  the surcharge.
- The implemented decisions are:
  - Pickup and destination share a TODA: only drivers from the shared TODA
    set are eligible and no boundary surcharge is charged.
  - Pickup is covered but the destination shares no pickup TODA: drivers from
    the pickup TODA set are eligible and one outside-TODA surcharge is charged.
  - At least one valid geofence exists but pickup is in none: booking is
    rejected as outside the configured service area.
  - No valid geofence exists anywhere: the booking is tagged
    `unconfigured_fallback` and legacy open dispatch remains enabled for pilot
    testing. This fallback must be removed or placed behind a developer
    setting before strict production rollout.
- Overlapping zones are not assigned by Firestore document order. Matching
  TODA IDs are sorted, and every shared/pickup jurisdiction remains eligible;
  the booking records a null single `serviceTodaId` when ownership is
  genuinely multiple.
- Each booking snapshots the pickup/destination/shared/eligible TODA sets,
  coverage class, service TODA, matching coverage revisions, fare-config
  version, complete fare line items, checked restriction IDs, and the
  authoritative route polyline when Google supplies one.
- The authoritative PHP formula is:
  `base fare + ceil(max(0, metres - included metres) / step metres) * step
  price + additional passengers * passenger fee + baggage * baggage fee +
  one cross-boundary surcharge`.
- Flutter now reads `outsideTodaSurcharge` with
  `outOfBarangayFee` as a legacy fallback. Before booking it refreshes
  coverage/restrictions, shows the calculated line items and warning icon,
  then consumes the callable's authoritative distance, outside-zone result,
  fare breakdown, and total instead of discarding the server response.

### Driver search and simultaneous acceptance

- Candidate search uses approved, online, available drivers; active matching
  TODA; active user; verified suitable vehicle/capacity; current licence; no
  current booking; RTDB location no older than 35 seconds, no more than 100 m
  accuracy, and no more than five kilometres from pickup.
- Eligible drivers are sorted by pickup distance and stable driver ID. The
  nearest five receive simultaneous offers containing distance, rank,
  coverage revision, offer round, and expiry.
- Accept is now a short server-owned arbitration instead of raw transaction
  arrival order. Claims collected during the 1.5-second window are sorted by
  service priority, trusted pickup distance, server acceptance time, and
  driver ID. Therefore, if a near and far offered driver both accept inside
  that window, the nearer still-eligible driver wins; equal-distance drivers
  resolve by accepted time and then ID.
- Booking assignment, driver reservation, winning offer, operation record,
  claims, and audit entry are committed in one transaction. Losing callers
  receive a clear aborted result, and one driver cannot decline away the
  still-active offers of its peers.
- Search is server-expired at 60 seconds and offers are capped inside that
  deadline. Timeout cancellation waits for an in-progress acceptance window
  to finish, so a valid claim is not cancelled mid-award.

### Route restrictions and warnings

- `prohibited_highway` is stored as one centreline plus a 5-200 metre buffer.
  `no_service_area` and `restricted_crossing` support one or more disconnected
  polygons.
- The backend rejects no-service endpoints, requests Google route
  alternatives with encoded polylines, checks every route segment against
  polygon edges and buffered corridor segments, and prices the first allowed
  route. It rejects the booking when no safe alternative exists.
- Flutter geometry parsing supports v2 and legacy records. Passenger route
  selection now refreshes restrictions and uses the same segment-level
  checks. Existing driver guidance keeps the compact Material warning icon,
  tells a driver in a restricted area to leave by a safe route, and does not
  disable ride or SOS controls. The large PNG asset was not used.

### Rust boundary

- Rust/Cargo 1.94.0 was already installed. It was not updated, and no Rust
  bridge was added. Firebase authorization, transactions, RTDB, Google
  routing, notifications, and admin calls remain in the existing JavaScript
  boundary. The proposed app-wide Flutter/TypeScript-to-Rust migration remains
  a separate architecture project.

### Verification evidence

- `dart format`: completed for all changed Dart and Dart test files.
- `flutter analyze`: no issues; full run completed in 182.9 seconds.
- `flutter test`: 108 tests passed.
- Functions `npm test`: 37 tests passed.
- `node --check`: passed for Functions, emulator seed, and emulator lifecycle
  verification scripts.
- Admin `tsc --noEmit`: passed.
- Admin production `npm run build`: passed; Vite emitted only its existing
  large-chunk optimization warning and refreshed `admin/dist`.
- `git diff --check`: passed with line-ending notices only.

### Remaining deployment and scale limits

- The Firebase emulator lifecycle could not be executed because Firebase CLI
  is not installed in this workspace. Its expanded script is syntax-checked
  but still needs a real emulator run.
- No Functions, rules, Firestore data, or Hosting deployment was performed.
  The reported production `functions/internal` path is structurally fixed in
  source but remains unverified in the deployed project until these Functions
  and the rebuilt admin are deployed together.
- Driver enumeration is capped at 500 approved/online/available documents.
  The 60-second search normally exposes only the nearest five unless peer
  declines trigger another batch; a geo-index/sub-minute tier scheduler is
  still needed for platform-scale dispatch.
- Overlapping TODA zones currently allow every deterministic match rather than
  using a developer-set exclusive priority.
- The native Navigation SDK may independently reroute away from the backend
  polyline. Live point warnings remain a safety backstop, not physical vehicle
  enforcement or a verified custom-route handoff.
