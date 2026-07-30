# VolTrike Mobile App-Wide Dark Mode TODO

Status: implementation complete; automated validation passed. Remaining
unchecked items are real-device/manual visual checks or explicitly deferred
hardening, not blockers found by the automated suite.

This plan treats the requested feature as dark mode. The implementation record,
test evidence, improvements, and intentional exclusions are in `done.md`.

## Scope contract

In scope:

- The Flutter mobile app after a passenger or driver signs in.
- Passenger and driver shells, home, dashboard, trips, profile, and settings.
- Booking, searching, tracking, navigation, chat, calls, rating, receipts, and
  ride dialogs.
- Shared mobile widgets, maps, system bars, About, legal documents opened from
  Settings, and the license page.
- A persisted Dark mode toggle at Profile -> Settings -> Appearance.

Out of scope:

- Everything under `admin/`.
- Splash, intro, login, forgot-password, email-verification, passenger
  registration, driver registration/upload/review, and under-review UI.
- Registration legal acknowledgements. The same Privacy and Terms screens may
  use dark mode when opened from signed-in Settings, but must remain light when
  opened with `?acknowledge=true` during registration.
- Business logic, booking-state behavior, backend schemas, Firebase rules, and
  admin preferences unless a narrowly required theme hook is identified.

Default and persistence behavior:

- [x] Keep Light mode as the default for existing and new installs.
- [x] Apply a theme change immediately without restarting or losing current
  passenger/driver/ride state.
- [x] Save the preference locally on the device.
- [x] Restore it before the first signed-in frame to prevent a light flash.
- [x] Keep the saved preference through logout/login while all public/auth
  screens remain visually light.
- [x] Use one device-level preference shared by passenger and driver sessions;
  do not add a Firestore field or admin setting.

## Definition of done

- [ ] Every reachable post-auth mobile surface is usable in Light and Dark.
- [ ] No accidental white panels, dark-on-dark text, or light-on-light icons.
- [ ] Normal text reaches at least 4.5:1 contrast; large text, meaningful icons,
  focus indicators, and control boundaries reach at least 3:1.
- [ ] Interactive targets are at least 48 logical pixels where practical.
- [ ] Key layouts fit at 320x568 and 430x932 in portrait at text scales 1.0,
  1.5, and 2.0 without clipped actions or hidden essential information.
- [ ] Maps, route lines, markers, native navigation controls, bottom sheets,
  keyboards, dialogs, snackbars, and system bars are readable in both modes.
- [ ] VolTrike still looks like VolTrike: teal brand family, Poppins,
  rounded cards, calm spacing, clear hierarchy, and green/amber/red semantics.
- [x] Auth/registration remains visually unchanged even when Dark mode was
  previously selected.
- [x] `flutter analyze` and the full Flutter test suite pass.
- [x] `done.md` is updated with actual changes, improvements, validation, and
  any intentionally deferred item.

## 1. Theme state and route boundaries

- [ ] Add `shared_preferences` and a small injected `ThemePreferenceStore` in
  `lib/core/`; theme is ordinary device-local UI state, not sensitive account
  data. Use a versioned key such as `voltrike.dark_mode.v1` and safely fall
  back to Light on missing, invalid, or unreadable values.
- [ ] Add a Riverpod theme-mode controller/provider with only the two supported
  values: Light and Dark.
- [ ] Update state immediately on toggle, persist it, and roll back with a
  readable non-blocking error if the write fails.
- [ ] Load the stored value before `runApp` and inject the store/initial value
  through `ProviderScope` so signed-in UI does not flash.
- [ ] Convert `VolTrikeApp` to a Riverpod consumer and bind
  `MaterialApp.router.themeMode` to the controller.
- [ ] Keep `theme`, `darkTheme`, routing, localization behavior, and keyboard
  dismissal centralized in `lib/app/app.dart`.
- [ ] Add a reusable fixed-light `Theme` plus `AnnotatedRegion` boundary for
  public/auth content.
- [ ] Apply that boundary in `lib/app/router.dart` to splash, intro, login,
  forgot password, verification, suspension, all passenger/driver
  registration routes, registration success, and driver under-review.
- [ ] Conditionally force Privacy/Terms to Light only when
  `acknowledgementRequired` is true; let the Settings versions inherit the
  selected app theme.
- [ ] Confirm direct `MaterialPageRoute` pushes, GoRouter pushes, dialogs,
  modal sheets, and the license page receive the intended theme.
- [ ] Do not edit auth/registration screen implementations or add a theme
  control anywhere in those flows.

## 2. VolTrike light and dark design systems

- [ ] Replace `AppTheme.darkTheme = lightTheme.copyWith(...)` with a complete,
  explicit dark `ColorScheme`.
- [ ] Keep the current Light palette visually stable to avoid an unrelated
  redesign.
- [ ] Use deep blue-green/charcoal scaffold and surface tones instead of pure
  black, with a lighter teal primary accent that remains recognizably
  VolTrike.
- [ ] Define paired foreground colors (`onPrimary`, `onSurface`,
  `onSurfaceVariant`, `onError`, and container on-colors); never assume white
  is valid for every colored background.
- [ ] Add a `ThemeExtension` for VolTrike semantic roles not fully represented
  by `ColorScheme`: success, warning, info, rating, call, chat, report, and
  safety, including matching foreground/container colors for Light and Dark.
- [ ] Make post-auth text obtain neutral colors from `TextTheme`/`ColorScheme`
  rather than the light-only colors embedded in `AppTextStyles`.
- [ ] Make normal `labelLarge` text use an on-surface color; let button themes
  supply on-primary/on-secondary colors. The current globally white
  `labelLarge` can disappear on pale cards even before Dark mode.
- [ ] Preserve Poppins sizes and weights; avoid shrinking important text with
  `FittedBox` merely to hide overflow.
- [ ] Build complete Light/Dark component themes for app bars, inputs,
  selection/cursors, cards, list tiles, switches, buttons, icon buttons,
  navigation bars, dialogs, bottom sheets, chips, segmented buttons, dividers,
  snackbars, progress indicators, tooltips, menus, date pickers, and license
  UI.
- [ ] Use tonal surface separation and outlines in Dark mode; reduce
  light-oriented drop shadows that do not read correctly on dark surfaces.
- [ ] Give disabled controls explicit readable foreground/background pairs.
- [ ] Centralize brightness-aware status/navigation-bar styles and remove the
  current globally fixed dark-icon/white-navigation-bar styling.
- [ ] Do not reuse the current light foreground tokens unchanged on dark
  surfaces: the audit measured roughly 3.00:1 for current primary, 3.36:1 for
  current secondary text, and 3.59:1 for current error red on a dark surface.
  Select and test dark-specific tones before committing the palette.

## 3. Profile -> Settings toggle

- [ ] Add an `Appearance` `ProfileSection` to
  `lib/features/common/presentation/widgets/settings_view.dart`, between
  Account and About/legal.
- [ ] Add one accessible `SwitchListTile` titled `Dark mode`, with a short
  explanation that it changes the signed-in app appearance.
- [ ] Use a moon/sun or dark-mode icon whose color comes from the active theme.
- [ ] Read and update the shared Riverpod controller; do not duplicate state
  in passenger and driver settings screens.
- [ ] Keep the entire row tappable, expose the selected state to semantics, and
  retain a minimum 48-pixel switch target.
- [ ] Show the new appearance section through both existing paths:
  Passenger Profile -> gear -> Settings and Driver Profile -> gear -> Settings.
- [ ] Keep logout confirmation buttons on `error/onError` and verify the
  setting remains saved after logout.

## 4. Shared core and common mobile UI

- [ ] Update `AppScaffold`, `SectionTitle`, `AppCard`, `BookingCard`,
  `StatusCard`, `SearchField`, `AppTextField`, and shared buttons to use theme
  surfaces, text, outline, primary, disabled, and error roles.
- [ ] Update success/error/confirmation dialogs and the loading overlay so
  their cards, icons, messages, barriers, and actions work in both modes.
- [ ] Update `SnackbarService` and shared star-rating colors to use the active
  snackbar and semantic-rating theme roles.
- [ ] Keep the Light rendering of shared widgets used by auth unchanged.
- [ ] Update shared `AppAppBar`, shell, bottom navigation, loading/empty/error
  states, profile avatar, and permission cards only where the complete theme
  does not already supply the right value.
- [ ] Consolidate or dark-proof both existing `EmptyState` implementations so
  future screens cannot accidentally select the fixed-light version.
- [ ] Update `profile_widgets.dart`: avatar container, fallback icon, status
  badge, and information-tile icon containers must use theme/container pairs.
- [ ] Update `dashboard_widgets.dart`: metric accents, money/status colors,
  empty-trip icon, locations, fare, and badges must use dynamic semantic roles.
- [ ] Replace fixed 116-pixel metric-card sizing with an adaptive minimum
  height or responsive layout at large text.
- [ ] Let dashboard status/action/footer rows wrap or stack instead of clipping.
- [ ] Make the emergency-contact dialog scroll above the keyboard at large
  text; keep its fields and destructive action themed.
- [ ] Use the dark logo asset on light surfaces and the light logo asset on
  dark surfaces in About VolTrike.
- [ ] Verify Privacy, Terms, About, system diagnostics, emergency contacts, and
  the open-source license page in both signed-in modes.

## 5. Passenger screens and widgets

### Shell and home

- [ ] `passenger_shell_screen.dart`: verify all four destinations inherit the
  selected navigation theme and keep their tab state during a live toggle.
- [ ] `passenger_home_screen.dart`: theme map tiles and overlays; make the home
  draggable sheet account for safe areas, small heights, and text scaling.
- [ ] `home_bottom_sheet.dart`: replace the fixed grey drag handle with
  `outlineVariant`; verify pickup/destination, fare, and options in both modes.
- [ ] `location_search_bar.dart`: use a themed outline/elevation so the field
  remains distinct over light and dark maps.
- [ ] `fare_card.dart`: restore a themed surface/outline instead of overriding
  the global card shape; let long fare values wrap safely.
- [ ] `trip_options_card.dart`: adapt the label/value/control row on narrow
  widths and at 1.5x/2.0 text.

### Search, booking, and tracking

- [ ] `destination_search_screen.dart`: verify scaffold, keyboard, search
  progress, empty/error states, and result dividers in both modes.
- [ ] `place_tile.dart`: replace every fixed light title, subtitle, icon,
  recommendation, distance-pill, surface, and border color with scheme or
  semantic tokens.
- [ ] `searching_driver_screen.dart`: replace fixed orange/blue/green/red/grey
  states with paired semantic container/foreground roles; do not use low
  contrast white-on-orange.
- [ ] Make the searching state card scroll/adapt on a short screen or at large
  text instead of relying on one centered non-scrollable column.
- [ ] `booking_tracking_screen.dart`: theme the map, cards, overlays,
  restriction banners, sheet separation, dialogs, and quick actions.
- [ ] Remove or repair the unreachable empty-booking branch containing an
  invalid `Expanded` under a `Stack`; do not leave a latent layout failure.
- [ ] Calculate map padding from the visible bottom sheet/safe area so native
  controls, attribution, markers, and route endpoints remain visible.
- [ ] Keep pickup, driver, and destination distinguishable by icon/shape and
  label as well as color.

### Dashboard, trips, profile, and completion

- [ ] `passenger_dashboard_screen.dart`: migrate success/warning/error/rating
  accents, fix weak warning text, and make metrics/latest-trip actions adapt.
- [ ] `passenger_trip_history_screen.dart`: verify filters, loading/empty/error
  states, cards, detail navigation, receipt, rating, and report paths.
- [ ] `passenger_profile_screen.dart`: migrate active/verification/rating/
  favorites and avatar accents to dynamic semantic colors.
- [ ] `passenger_settings_screen.dart`: show the shared Appearance control and
  use dynamic error/onError colors in logout confirmation.
- [ ] `edit_passenger_profile_screen.dart`: verify avatar fallback/border,
  date picker, text fields, image picker state, save progress, keyboard, and
  long values in both modes.
- [ ] `rating_screen.dart`: migrate fixed text/container colors and make the
  five-star input fit narrow widths and large text.
- [ ] `trip_receipt_screen.dart`: verify the summary/status panel, fixed-width
  label column, long amounts/addresses, and persistent bottom action.
- [ ] `driver_information_card.dart`: re-test driver identity and ride actions
  at 2.0x text; retain its existing good `ColorScheme` usage.

## 6. Driver screens and widgets

### Shell, home, and booking offer

- [ ] `driver_shell_screen.dart`: verify all four destinations, active-booking
  redirection, and live theme changes without losing current ride state.
- [ ] `driver_home_screen.dart`: theme the map and bottom overlays; account for
  overlay height in map padding.
- [ ] `booking_request_card.dart`: migrate fixed green/red actions, add a
  dark-visible outline/elevation over the map, wrap metrics/actions, and allow
  readable multi-line addresses.
- [ ] Constrain/scroll the incoming booking overlay on short screens and at
  large text.
- [ ] `driver_bottom_sheet.dart`: replace fixed white/grey/red colors with
  surface, outline, on-surface, and error roles.
- [ ] Make idle and every active ride state height-constrained and scrollable
  so confirmation controls and Cancel remain reachable.

### Tracking and navigation

- [ ] `driver_booking_tracking_screen.dart`: migrate red/teal light-only
  instruction/restriction panels to error/secondary container pairs.
- [ ] Remove or fix the latent empty-booking branch rather than leaving a
  light-only fallback.
- [ ] Add visible separation between the dark sheet and dark map.
- [ ] Base map padding on the actual collapsed sheet and safe-area height.
- [ ] Reuse the branded marker factory and distinct pickup/destination markers
  so meaning is not communicated by color alone.
- [ ] `driver_turn_by_turn_map.dart`: synchronize native navigation night mode
  with the selected app mode without restarting guidance.

### Dashboard, earnings, trips, and profile

- [ ] `driver_dashboard_screen.dart`: migrate online/offline, success, warning,
  error, rating, and primary accents; adapt metric and action layouts.
- [ ] `driver_earnings_screen.dart`: use the shared app-bar/card identity and
  verify long currency values, errors, and large text in both modes.
- [ ] `driver_trip_history_screen.dart`: verify filters/cards/detail/receipt/
  report paths and preserve driver-view labels.
- [ ] `driver_profile_screen.dart`: migrate online/offline, licence,
  approval, rating, completed-trip, and earnings accents.
- [ ] `driver_settings_screen.dart`: show the shared toggle and use the dynamic
  destructive palette for logout.
- [ ] `edit_driver_profile_screen.dart`: verify avatar, date picker, form,
  image state, save progress, keyboard, and long licence/phone values.
- [ ] `driver_map_view.dart`: inherit the selected map scheme and retain a
  high-contrast route line and meaningful markers.
- [ ] `passenger_information_card.dart`: retain its good scheme usage and
  re-test it alongside larger ride-action controls.

## 7. Shared ride, history, chat, and call UI

- [ ] `trip_history_card.dart`: migrate avatar, connector, route text/icons,
  status badge, chevron, fare, distance, and rating to dynamic theme roles.
- [ ] Make its top identity/status and bottom fare/distance/rating rows wrap at
  narrow widths and large text.
- [ ] `trip_history_detail_screen.dart`: migrate avatar/info containers,
  completion/cancellation panels, and the fixed light bottom action surface.
- [ ] `trip_history_view.dart`: make the three-state segmented filter scroll or
  adapt rather than overflow at 320px/large text.
- [ ] `booking_chat_screen.dart`: migrate composer, border, incoming/outgoing
  bubbles, message/timestamp text, empty state, and send button to
  surface/on-surface and primary/on-primary pairs.
- [ ] Verify chat keyboard insets, long messages, timestamps, typing state,
  seen state, and snackbar alerts.
- [ ] `ride_quick_actions.dart`: use semantic action foreground/background
  pairs, correct report-action contrast, and raise 42-pixel controls to at
  least 48 pixels.
- [ ] `ride_actions_card.dart`: allow action buttons to grow or stack when
  labels wrap instead of forcing a clipping fixed height.
- [ ] `ride_confirmation_slider.dart`: add a readable disabled foreground,
  support long/two-line confirmation labels, and keep the thumb target >=48.
- [ ] Keep `trip_status_card.dart`, `trip_information_card.dart`,
  `ride_cancel_dialog.dart`, and the main tracking cards scheme-driven; add
  Light/Dark regression coverage rather than unnecessary redesign.
- [ ] `report_ride_dialog.dart`: use `colorScheme.error` and verify the
  scrollable form/actions.
- [ ] Smoke-test all `RideSafetyService` SOS, status, contact, and 911 dialogs
  under both themes.
- [ ] Keep `voice_call_screen.dart` and `incoming_call_screen.dart`
  intentionally immersive dark in both app modes.
- [ ] Give call screens their own guaranteed high-contrast accent/on-colors;
  do not let a changing app primary create unreadable icons or controls.
- [ ] Force light status/navigation-bar icons over call backgrounds and verify
  muted, disabled, decline, accept, timeout, and ended states.

## 8. Google map and native navigation theming

- [ ] Extend `lib/core/maps/voltrike_map.dart` so the app-owned map wrapper
  selects native `MapColorScheme.light` or `.dark` from the inherited theme.
- [ ] Pass `initialMapColorScheme` to prevent a bright map flash.
- [ ] Reapply `setMapColorScheme` when the toggle changes while a map is
  mounted; do not recreate markers/routes unnecessarily.
- [ ] For `GoogleMapsNavigationView`, use matching force-day/force-night
  behavior while navigation UI is enabled, and update it dynamically.
- [ ] No package upgrade is required for the pinned
  `google_navigation_flutter 0.9.2`; light/dark controls were introduced in
  0.8.0. Verify API details against the
  [official changelog](https://github.com/googlemaps/flutter-navigation-sdk/blob/main/CHANGELOG.md)
  and [package documentation](https://pub.dev/packages/google_navigation_flutter).
- [ ] Verify traffic colors, the blue route stroke, attribution, native map
  buttons, compass/recenter controls, custom markers, info windows, and loading
  placeholders on a real Android platform view.
- [ ] Toggle Light/Dark while passenger home, passenger tracking, driver home,
  fallback driver tracking, and active turn-by-turn navigation are mounted.

## 9. Dormant or duplicate UI found during the audit

These files are not currently reachable in the runtime flow. They were still
audited so they do not silently expand the release scope.

- [ ] Re-run reference searches immediately before implementation to confirm
  reachability.
- [ ] Keep the duplicate
  `lib/features/passenger/presentation/screens/driver_trip_history_screen.dart`
  out of the runtime migration; schedule deletion separately if desired.
- [ ] Treat legacy `ride_bottom_sheet.dart`, `ride_status_card.dart`,
  `ride_information_card.dart`, `ride_primary_button.dart`,
  `ride_secondary_actions.dart`, `ride_map_controls.dart`, and
  `expandable_trip_card.dart` as deferred unless a live reference reappears.
- [ ] If any dormant widget is retained/reconnected, make it scheme-driven and
  fix known row/fixed-height overflow before calling dark mode app-wide.
- [ ] Do not combine dead-code cleanup with the dark-mode change without
  explicit approval.

## 10. Automated validation

- [ ] Unit-test preference parsing, default Light fallback, persistence, and
  storage failure behavior using an injected fake store.
- [ ] Widget-test the shared Settings Appearance section, switch semantics,
  immediate repaint, and both passenger/driver settings paths.
- [ ] Test that a saved Dark preference affects signed-in routes.
- [ ] Test that splash/intro/login/verification/registration/under-review and
  acknowledgement legal routes remain Light with a saved Dark preference.
- [ ] Add Light/Dark theme construction tests for brightness, ColorScheme,
  component themes, semantic extension, and system UI values.
- [ ] Add contrast tests for primary, surface, status, warning, error, rating,
  chat, quick actions, and disabled controls.
- [ ] Extend existing shell, trip history, trip information, quick actions,
  confirmation slider, and ride action tests to run in both themes.
- [ ] Add overflow tests at 320x568 and 430x932 with text scales 1.0, 1.5, and
  2.0 for the high-risk cards, sheets, segmented filters, chat, and actions.
- [ ] Confirm every widget test finishes with `tester.takeException() == null`.
- [ ] Run Dart formatting on changed Dart/test files.
- [ ] Run `flutter analyze`.
- [ ] Run the complete `flutter test` suite.
- [ ] Confirm `git diff --check` and review that `admin/` and auth/registration
  screen sources have no unintended changes.

## 11. Manual visual and interaction pass

- [ ] Passenger: home/map, destination results, fare/options, searching,
  matched/tracking/on-trip states, cancel/report/SOS, chat, call, rating,
  receipt, dashboard, trips/detail, profile/edit/settings, About/legal/license.
- [ ] Driver: offline/online home, incoming offer, fallback map,
  turn-by-turn guidance, every ride action, cancel/no-show/payment, chat, call,
  receipt, dashboard/earnings, trips/detail, profile/edit/settings.
- [ ] Capture before/after Light and Dark screenshots for representative
  passenger and driver flows.
- [ ] Check keyboard opening, back navigation, sheet dragging, route pushes,
  dialog dismissal, toggle while riding, restart, logout, and login.
- [ ] Confirm the selected mode never changes booking, location, notification,
  map-route, chat, call, or navigation state.
- [ ] Record every completed improvement and any evidence in `done.md`.

## Planned execution order after approval

1. Preference store, Riverpod controller, real themes, system UI, and
   fixed-light auth route scope.
2. Shared Settings toggle and common/core token migration.
3. Passenger screens and shared ride/history/chat UI.
4. Driver screens, maps, and native turn-by-turn navigation.
5. Responsive/large-text fixes found by the audit.
6. Automated tests, real-device visual pass, and `done.md` handoff.

## 12. Searching-driver radar and timeout redesign

- [x] Replace the large centered status card with animated orange radar rings
  centered on the pickup map camera.
- [x] Keep destination and route context visible without duplicating the
  pickup marker under the radar animation.
- [x] Move search status and actions into a rounded, theme-aware bottom sheet.
- [x] Show `Looking for a driver`, capacity-aware supporting copy, a live
  countdown, and a progress indicator.
- [x] Add a full-width red `Cancel request` button with loading and error
  feedback.
- [x] Use the existing 60-second booking timeout and calculate it from
  `booking.createdAt`, so reopening the screen cannot restart the countdown.
- [x] At expiry, atomically cancel only a still-pending request and close its
  outstanding driver offers.
- [x] Never let a timeout cancel a booking that a driver has already accepted.
- [x] Always use `No drivers available` as the terminal heading, with specific
  copy for high-capacity electric tuktuks and unserved areas.
- [x] Retry timeout cancellation safely when connectivity temporarily fails.
- [x] Add countdown, capacity, service-area copy, and backend timeout-policy
  tests.
- [ ] Smoke-test the radar alignment and bottom-sheet height on a real Android
  Google Maps platform view.

## 13. TODA coverage, zone-aware booking, fare, and route restrictions

Status: scoped implementation complete; local automated validation passed.
Deployment, emulator lifecycle execution, native-route handoff, overlap
priority, and platform-scale dispatch work remain below.

This section is additive. It does not reopen or replace the earlier dark-mode
work. The feature boundary is TODA coverage persistence, authoritative booking
classification, zone-aware dispatch, fare breakdown, and route restrictions.

### Architecture and Rust boundary

- [x] Audit the Flutter, React/TypeScript admin, Firebase Functions,
  Firestore/RTDB, fare, dispatch, coverage, and restriction paths before
  changing behavior.
- [x] Confirm the installed Rust toolchain is already stable Rust/Cargo 1.94.0
  and that this repository currently has no Cargo workspace, Rust source,
  generated bridge, FFI, N-API, or WebAssembly integration.
- [x] Keep Firebase authentication, callable authorization, Firestore/RTDB
  reads and writes, transactions, triggers, and notifications in the existing
  JavaScript Firebase Functions boundary for this feature.
- [ ] If Rust is introduced here, restrict it to a small deterministic policy
  core such as coordinate validation, point-in-polygon, route-conflict
  geometry, fare breakdown, and candidate scoring. Keep network access and
  Firebase credentials out of Rust, and verify identical results at the
  JavaScript/Dart boundary.
- [x] Explicitly defer the proposed app-wide Flutter -> Rust -> JavaScript and
  React/TypeScript -> Rust -> JavaScript migration. Do not rewrite unrelated
  repositories, providers, screens, admin pages, or Cloud Functions in this
  feature.
- [x] Do not update Rust merely for this work; reconsider the toolchain only
  when a chosen bridge or build target documents a newer minimum version.

### Coverage request persistence and approval

- [x] Replace Firestore-incompatible nested coordinate arrays with a versioned,
  unambiguous shape such as `areas: [{points: [{latitude, longitude}]}]`.
  Accept legacy `[longitude, latitude]` input only at a validation adapter and
  never persist latitude/longitude as positional arrays again.
- [x] Validate finite values, longitude/latitude ranges, point and area limits,
  duplicate/degenerate edges, minimum polygon area, and self-intersection
  before writing a coverage request or route restriction.
- [x] Preserve role boundaries: a TODA admin may submit only for its own TODA;
  a developer admin may create for a selected TODA, edit a pending request,
  and approve or decline it.
- [x] Add explicit request state/version guards so an already reviewed request
  cannot be silently edited or reviewed twice, and an older approval cannot
  overwrite a newer active coverage revision.
- [x] Publish one active, revisioned geofence per TODA atomically with the
  approval decision and immutable audit record. Keep the submitted geometry
  as review history.
- [x] Surface safe callable validation messages in the admin
  UI while logging the server-side cause with request/TODA identifiers.
- [x] Let the developer review the submitted polygons on the map, edit before
  approval, and create a test coverage polygon for the current barangay
  without weakening production zone checks.

### Authoritative booking-zone and fare policy

- [x] Classify pickup and destination against approved active geofences in the
  backend. Do not trust a client-supplied `isOutsideToda`, TODA ID, zone ID, or
  boundary surcharge.
- [x] Use pickup jurisdiction for dispatch: when pickup and destination are in
  the same approved TODA coverage, offer only to eligible drivers of that TODA
  and apply no outside-TODA surcharge.
- [x] When pickup is in TODA A and destination is outside A or in TODA B,
  dispatch TODA A drivers and apply the configured outside-TODA surcharge once.
  Any cross-TODA fallback must be an explicit developer-controlled policy, not
  an automatic leak across TODA boundaries.
- [x] Reject an uncovered pickup whenever at least one valid active geofence
  exists. Preserve and snapshot an explicit `unconfigured_fallback` only when
  the project has no valid coverage at all, so barangay pilot testing remains
  possible.
- [ ] Replace the automatic zero-geofence pilot fallback with a
  developer-controlled setting before strict production rollout.
- [ ] Define and reject ambiguous overlapping active TODA coverage, or resolve
  it with a stored developer-approved priority; never depend on Firestore
  document order.
- [x] Snapshot `serviceTodaId`, pickup/destination coverage results, geofence
  revision, boundary classification, fare-config version, and a complete
  backend fare breakdown on the booking.
- [x] Keep the authoritative formula as base fare plus started distance steps,
  additional-passenger fees, baggage fees, and one boundary surcharge, all
  rounded and stored in PHP.
- [x] Fix the mobile fare mapping mismatch between
  `outsideTodaSurcharge` and the legacy `outOfBarangayFee`, then render the
  backend-confirmed breakdown rather than relying on a client-only estimate.

### Zone-aware dispatch and simultaneous acceptance

- [x] Apply hard eligibility filters before ranking: active user, approved and
  available driver, active matching TODA, verified suitable vehicle, current
  licence, no active booking, fresh/accurate online RTDB location, required
  capacity, and pickup within the configured five-kilometre radius.
- [x] Rank eligible same-TODA drivers by trusted driver-to-pickup distance
  with a stable tie-breaker. Record rank, distance, zone revision, offer round,
  and expiry in each offer.
- [x] Offer the nearest five simultaneously and collect accept claims for a
  1.5-second server window. Award the nearest still-eligible accepting driver,
  then use server acceptance time and driver ID as stable tie-breakers.
- [x] Keep booking assignment, driver reservation, accepted-offer state, and
  audit data in one Firestore transaction so two drivers can never both win.
  Return a clear `already accepted` result to the losing driver.
- [x] Ensure a single driver's decline or withdrawn claim does not expire the
  other still-valid offers in the same batch.
- [ ] Add a sub-minute tier scheduler and driver offer countdown aligned with
  the 60-second passenger search. The current 55-second first batch normally
  leaves no useful scheduled second round.
- [ ] Replace the current 500-document driver cap with a safe geo-indexed
  candidate prefilter before claiming platform-scale nearest dispatch.

### Restriction enforcement and driver warning

- [x] Store restriction geometry in the same coordinate-map schema as coverage
  data. Keep highway corridors as centreline points plus a metre buffer and
  no-service/crossing restrictions as one or more polygons.
- [x] Give each restriction type explicit behavior:
  `no_service_area` rejects endpoints and crossing routes;
  `restricted_crossing` rejects intersecting routes; and
  `prohibited_highway` rejects routes entering its buffered corridor.
- [x] Validate route segments against polygon edges and corridor segments, not
  only decoded route vertices, so a sparse polyline cannot jump across a
  narrow restriction undetected.
- [x] Make the backend request and inspect route alternatives before accepting
  a booking, then calculate fare from the selected allowed route. Keep mobile
  checks for immediate UX, but never make them the only enforcement layer.
- [ ] Address native Navigation SDK rerouting separately: the current native
  session may choose a different route from the prechecked REST polyline.
  Until a verified route-token/custom-route handoff exists, warn and stop
  guidance when a restricted route is detected rather than claiming physical
  geofence enforcement.
- [x] Show a compact accessible warning banner in driver guidance. Prefer the
  existing Material warning icon; if `assets/icons/warning.png` is used,
  resize/optimize the 2100x2100 source before displaying it as a small icon.
- [x] Keep essential ride/SOS controls enabled when a driver is inside a
  restriction and show guidance to leave by a safe route.
- [ ] Persist an audit event for live driver restriction entry/exit and add a
  verified native custom-route handoff or stop-guidance policy.

### Validation and handoff

- [x] Add pure policy tests for coordinate parsing, boundary-inclusive
  point-in-MultiPolygon, overlaps, segment/corridor conflicts, zone
  classification, stable ranking, fare breakdown, and legacy parsing.
- [ ] Extend the isolated Firebase emulator seed with a barangay test geofence,
  at least two TODAs/drivers, and representative restriction geometries.
- [x] Extend the emulator lifecycle script for geometry-v2 approval,
  server-rejected restrictions, cross-boundary surcharge, and competing
  near/far accepts.
- [ ] Add remaining emulator cases for uncovered pickup, stale/wrong-TODA
  exclusion, peer decline/offer expiry, and a second TODA.
- [x] Add Flutter model/policy tests for coverage parsing/classification,
  fare-key compatibility, route-restriction geometry, and the authoritative
  callable booking quote.
- [ ] Add widget coverage for passenger and driver restriction warning states.
- [x] Run formatting, `flutter analyze`, the full Flutter suite, Functions
  tests and syntax checks, admin TypeScript/build, and `git diff --check`.
- [ ] Install or otherwise provide Firebase CLI, then execute the complete
  isolated emulator seed and lifecycle verification.
- [x] Record only completed implementation and actual validation evidence in
  the matching appended section of `done.md`.

## 14. Open-zone mutual aid, balanced dispatch, and segmented highways

This section supersedes the strict uncovered-pickup and pickup-TODA-only
assumptions in section 13. It preserves that earlier section as implementation
history while recording the current policy.

### Completed service and fare policy

- [x] Keep bookings serviceable when one or both endpoints are outside every
  approved TODA zone. If approved coverage exists, charge the configured
  Outside TODA surcharge exactly once; if no valid coverage exists anywhere,
  keep the barangay pilot fallback open with no boundary surcharge.
- [x] For TODA A pickup and TODA B destination, rank A as primary, B as
  secondary, and other active TODAs as mutual-aid fallback. Keep every
  candidate subject to availability, document, vehicle, location freshness,
  accuracy, capacity, active-booking, and five-kilometre checks.
- [x] When only one endpoint is covered, use its TODA set as the primary tier.
  When neither endpoint is covered in a configured network, let any active
  TODA serve at equal fallback priority.
- [x] Treat an overlap as shared jurisdiction when pickup and destination have
  at least one TODA in common. Sort all matching IDs, keep every shared TODA
  primary, charge no Outside TODA fee, and never choose ownership from
  Firestore document order.
- [x] Snapshot policy-v3 coverage class, primary/secondary TODA IDs,
  all-active-fallback permission, revisions, route decision, and the
  server-calculated fare breakdown on each new booking.

### Completed matching and queue policy

- [x] Offer at most five eligible drivers in the first batch while reserving a
  place for the nearest available secondary and fallback candidate when those
  tiers exist.
- [x] Arbitrate simultaneous accepts by hard TODA service tier, 100-metre
  pickup-distance band, fewer awards during the current Manila calendar day,
  smoothed reliability, smoothed rating, exact distance, server acceptance
  time, and stable driver ID.
- [x] Update protected driver dispatch statistics transactionally and store
  score snapshots/audit data so an award can be explained later.
- [x] Order multiple offers on the driver screen by the passenger's oldest
  queue-entry time, then service tier, pickup distance, and stable ID.
- [x] Keep the award transaction as the single source of truth when several
  drivers accept. Only one driver can reserve the booking; losing claims
  receive an already-awarded result.

### Completed segmented restriction policy

- [x] Let one highway restriction contain up to 20 disconnected centreline
  segments. Treat every red buffered segment as blocked and an intentionally
  wide blank gap as a legal cross-street opening.
- [x] Require the administrator to finish the current segment before saving;
  prevent a partial one-point segment from being silently discarded.
- [x] Check all stored corridor segments on both the Functions and Flutter
  paths, retain legacy one-line restrictions, and test blocked second
  segments, wide legal gaps, and gaps still closed by endpoint buffers.
- [x] Carry avoided restriction names into the booking response and passenger
  search state, then show a compact Material warning/advisory without using
  the oversized warning PNG.
- [x] Exercise open-pilot, A-to-B mutual aid, configured fully uncovered,
  one-time surcharge, competing acceptance, and segmented-highway behavior in
  the isolated `demo-voltrike` Firebase lifecycle.

### Remaining production and scale work

- [ ] Add a geo-index and sub-minute offer-tier scheduler. The current
  500-driver query cap, five-driver first batch, 55-second offer, and
  60-second passenger timeout are suitable for the present pilot, not
  platform-scale matching.
- [ ] Add a global multi-booking optimizer or short driver lease if dispatch
  must optimize several passengers and several drivers simultaneously. The
  current implementation orders each driver's visible offers and arbitrates
  each booking independently.
- [ ] Add an injectable HTTP client and direct Flutter test for Google Routes
  alternative selection/advisory propagation, plus automated admin
  Enter/max-20 interaction tests.
- [ ] Verify a live Google Routes response and the complete passenger/driver
  flow on physical devices. The deterministic emulator route does not prove
  every real Bacolod road alternative.
- [ ] Define a native Navigation SDK custom-route handoff or stop-guidance
  policy. A native reroute can still differ from the server-approved polyline.
- [ ] Integrate and monitor Flutter Firebase App Check before enabling
  enforcement. Current logs show invalid/missing tokens being allowed because
  enforcement is intentionally disabled.
- [ ] Deploy Functions and Firestore rules together, rebuild/deploy Hosting,
  then perform a controlled production field test. No production deployment
  is part of this implementation pass.
- [ ] Keep the proposed Flutter/TypeScript-to-Rust bridge as a separate
  app-wide architecture project; do not mix it into this dispatch rollout.

## 15. Provider highway avoidance, restricted-area monitoring, violations, and case chat

Status on 2026-07-30: the first runtime implementation is complete locally
across Functions, rules, Flutter, and Admin. Unit/static/build checks pass.
Production Firebase deployment, physical Bacolod field validation, App Check,
disciplinary policy, and later map-matched highway detection remain open.

This section supersedes the manual segmented-highway creation policy in
sections 13 and 14. Legacy records and parsers remain migration/audit concerns;
they must not be deleted merely because new corridor creation is removed.

### Accepted policy and terminology

- [x] Stop treating a hand-drawn buffered highway centreline as the long-term
  solution. It is too expensive to maintain and cannot reliably distinguish
  travelling along a highway from a legal perpendicular, bridge, or underpass
  crossing.
- [x] Keep `no_service_area` and legacy `restricted_crossing` MultiPolygons.
  Display the latter as `Restricted driving area` while retaining its database
  value for compatibility. Both types block pickup, destination, and route
  traversal.
- [x] Ask the route provider to avoid highways. With Google, treat
  `avoidHighways` as a routing preference and
  `routeRestrictionsPartiallyIgnored` as a route-level advisory, not proof
  that a driver travelled on a prohibited road.
- [x] Never classify a legal perpendicular highway crossing as a violation.
  A future confirmed highway-travel event requires sustained, map-matched road
  evidence and an official/legal road classification, not one GPS point.
- [x] Monitor restrictions only while the driver is online, including both
  idle/available and active-booking states. Stop location monitoring and
  restriction alerts when the driver goes offline.
- [x] Scope a violation to the driver's TODA at occurrence. Developer admins
  may review all cases; a TODA admin may review only cases owned by its TODA;
  the driver may review only its own cases; passengers have no access.
- [x] Use a separate violation-case conversation for driver, matching TODA
  admins, and developer admins. Reuse chat presentation patterns, but do not
  add admins to the passenger-driver booking chat.
- [x] Reuse the Live Drivers and Safety Incident map/list interaction patterns
  for a separate Violations page available to both admin roles. Use the same
  shared dark Mapbox style as the zone editor.

### Phase 0 - first implementation gate

- [ ] Checkpoint the already validated zone, open-service, fare, dispatch, and
  segmented-corridor work in a dedicated commit before changing its policy or
  schema.
- [ ] Inventory active `prohibited_highway` documents and snapshot their IDs,
  revisions, status, and usage before migration.
- [ ] Add rollout settings for provider highway avoidance, strict
  partially-ignored-route rejection, legacy-corridor enforcement, violation
  detection, and administrator alert delivery.
- [x] Hide new highway-corridor creation and make the backend reject new
  `prohibited_highway` writes, but retain read/parsing support and an archived
  history view until the replacement is field-proven.
- [ ] Define retention, appeal/dismissal, escalation, and false-positive
  policy before any violation is used for discipline. Telemetry must be
  described as operational evidence, not tamper-proof legal evidence.

### Phase 1 - server-owned contracts, security, and routing

- [x] Define a versioned `driverViolations/{violationId}` contract containing
  server-resolved driver/TODA ownership, context (`online_idle`,
  `to_pickup`, or `active_trip`), booking ID when present, restriction
  snapshot/revision, immutable event coordinates, accuracy/bearing/speed,
  source/confidence, entry/exit timestamps, workflow status, and delivery
  status.
- [x] Keep backend-only transition/cooldown state so repeated GPS writes do
  not create duplicate cases. Store an immutable event marker separately from
  the driver's current live marker.
- [ ] Add strict Firestore rules and indexes for developer-global,
  TODA-owned, and driver-owned reads. Keep event/state writes backend-only and
  keep internal administrator notes outside the shared driver chat.
- [x] Add a separate versioned violation-message contract. Send messages
  through an authenticated callable that validates case membership, text
  length and allowed fields, stamps sender identity/role and server time, and
  writes an audit record.
- [x] Harden RTDB location validation and the Admin live-location reader:
  reject stale/future or inaccurate samples, constrain allowed fields, avoid
  reading the entire location root for a TODA-scoped request, and document
  that client GPS can still be spoofed or suppressed.
- [ ] Add Firebase App Check to Flutter and Admin, monitor it before
  enforcement, and add Firestore/RTDB rules-emulator tests before relying on
  violation telemetry.
- [x] Make both retained polygon types explicitly reject pickup and
  destination points and every crossing route in Functions and Flutter.
- [x] Use the exact passenger outcomes:
  `E-trikes cannot pick up, drop off, or travel through this restricted area.
  Move the pin outside the red boundary.`,
  `Route adjusted to avoid <restriction name>.`, and
  `No permitted e-trike route is available for this trip.`
- [x] Send `avoidHighways: true`, request alternatives, and request/store
  `routeRestrictionsPartiallyIgnored` in both authoritative Functions routing
  and Flutter preview routing. The current pilot accepts a polygon-safe route
  with a strong advisory when Google partially ignores the preference and
  never describes an unflagged route as a legal guarantee.
- [ ] Put strict rejection of a partially ignored highway preference behind a
  rollout setting for controlled Bacolod comparison.
- [x] Apply equivalent highway-avoidance/custom-route policy to native
  navigation. Stop or warn on a native reroute that no longer matches the
  server-approved route until a verified custom-route handoff exists.

### Phase 2 - online driver warning and confirmed polygon entry

- [x] Add one app-wide `DriverRestrictionMonitor` fed by the existing driver
  location controller. It must remain active across driver screens while the
  backend-authoritative online state is true, including native navigation,
  and stop immediately when offline.
- [x] Add accuracy gating, approach distance, outside/approaching/inside/exit
  state, two reliable inside samples, hysteresis, and per-restriction cooldown
  so GPS jitter cannot repeatedly vibrate or open cases.
- [x] Show an amber approach banner and one short haptic near a restricted
  polygon. Show a persistent red entry banner, double haptic, optional spoken
  instruction, and a dedicated high-importance notification channel only on
  an entry transition.
- [x] Correct the Android foreground-service disclosure so it says that
  location is shared while the driver is online, not only during an active
  ride. Add an explicit online-idle/background-location privacy explanation
  and permission flow.
- [x] Have the backend independently validate fresh RTDB location, driver
  approval/online state, active restriction geometry/revision, consecutive
  samples, and transition state before creating one operational polygon case.
- [x] Record approach locally only. Persist operational entry and exit; permit a
  new case only after a real exit and cooldown.
- [x] Store Google `highway_route_advisory` data separately from polygon
  violations. Do not vibrate or alert at an alleged live highway
  crossing unless a later map-matching/official-road implementation can prove
  sustained prohibited-road travel.
- [x] Parse stored route advisory fields into booking and driver-offer models
  so the driver can see `Approved route avoids <restriction name>` before
  accepting and during guidance.

### Phase 3 - notifications, dark Mapbox operations map, and role pages

- [x] Extend the existing Functions notification-recipient pattern to active
  developer admins, active admins of the event's snapshotted TODA, and the
  affected driver. Deduplicate deliveries and persist attempted/succeeded
  status.
- [x] Add an Admin web FCM service worker, token registration, notification
  permission flow, and deep link such as
  `?page=violations&case=<violationId>`. Keep an in-app realtime listener and
  durable inbox; five-second visible-page polling alone is insufficient.
- [x] Extract a shared Admin operations map using
  `mapbox://styles/mapbox/dark-v11` so Live Drivers, Safety Incidents, and
  Violations use the same style as the zone editor.
- [ ] Extend the map contract beyond simple points to support a red immutable
  event marker, restriction MultiPolygon, optional current-driver marker, and
  a short privacy-limited breadcrumb. Reconcile markers by ID to avoid
  five-second refresh flicker.
- [x] Add a separate `Violations` navigation page for both Developer Admin and
  TODA Admin. Reuse the Live Drivers two-column layout and Safety Incident
  acknowledge/respond/resolve pattern, but never mix routine violations into
  SOS records.
- [x] Show open/acknowledged/responding/resolved/dismissed status, confidence
  and source, idle/trip context, restriction name/revision, booking link when
  applicable, occurrence time, accuracy, alert delivery, and map selection.
- [ ] Add filters for open state, event class, TODA (developer only), driver,
  restriction, booking context, confidence, and date. Export/reporting must
  preserve the event snapshot rather than substituting the driver's current
  location.
- [ ] Overlay an open-case badge on Live Drivers and provide a link to the
  case, while keeping the full workflow on the dedicated Violations page.

### Phase 4 - driver/admin case chat

- [ ] Extract reusable message-list/composer/read-state presentation from the
  booking chat without changing the existing passenger-driver contract.
- [x] Add the shared case thread to the Admin side panel and a driver
  restriction-case screen. Display sender name and role, timestamps, unread
  state, and the related event map summary.
- [ ] Add system status messages to the shared violation-case thread.
- [x] Deliver new case-message notifications to the driver and authorized
  admins with a case deep link. Do not notify or grant access to the passenger.
- [ ] Keep disciplinary notes, evidence review, and any enforcement decision
  in an admin-only audited record; the shared chat is for warning,
  clarification, and response.

### Phase 5 - tests, field validation, and controlled release

- [x] Add pure tests for approach/entry/exit state, boundary points,
  consecutive-fix confirmation, accuracy rejection, hysteresis, cooldown,
  exit/re-entry, advisory-versus-violation labeling, and stable
  deduplication.
- [ ] Add emulator coverage for spoof-resistant validation limits,
  server-owned event creation, developer/TODA/driver/passenger access,
  cross-TODA non-disclosure, message validation, unread state, audit records,
  FCM recipient selection, and Admin list indexes.
- [ ] Add Flutter controller/widget tests for online-idle, active booking,
  default native-navigation mode, foreground/background warnings, haptic
  transitions, offline privacy, notification taps, and case chat.
- [ ] Add Admin tests for role navigation, server scope, dark map marker and
  polygon layers, filters, selected-event persistence, alerts, response
  actions, chat, and deep links.
- [ ] Field-test real Bacolod routes and GPS on physical driver/passenger
  devices with the screen visible, backgrounded, and locked. Include legal
  perpendicular highway crossings, no-go polygon approach/entry/exit, poor
  GPS, native rerouting, app restart, and disabled notification vibration.
- [ ] Run provider highway avoidance and the legacy corridor system in
  comparison/shadow mode first. Archive rather than delete old corridors only
  after the official road list, exceptions, and field results are reviewed.
- [ ] Enable strict booking rejection and confirmed polygon alerts gradually,
  monitor false positives and delivery failures, and keep a rollback flag.
- [ ] Implement confirmed live highway-travel violations only after a later
  Mapbox map-matching or official-road-data phase can distinguish sustained
  travel from legal crossings. Mapbox basemap display alone is not evidence.
- [ ] Complete the directly related earlier work: live Google Routes device
  verification, native custom-route/stop-guidance policy, App Check,
  restriction-warning widget coverage, Admin map interaction tests, and a
  controlled joint Functions/rules/Hosting release.
- [ ] Keep geo-indexed dispatch, a global multi-booking optimizer, and the
  proposed app-wide Rust bridge as separate projects; they are not blockers
  for this safety/operations feature.

## Rust migration implementation - 2026-07-30

This tail section is the sole working checklist for the Rust migration. Earlier
sections remain historical and are not inputs to this implementation.

- [x] Capture the current Android/Flutter size, behavior, and performance
  baseline without changing product behavior.
- [x] Add an Android-first Rust workspace pinned to Rust 1.97.1 and a stable,
  reproducible Flutter bridge behind a hand-written Dart boundary.
- [x] Preserve a Dart fallback and add off/shadow/on rollout modes so bridge
  failure cannot block the working application.
- [x] Port one coarse-grained, pure geospatial batch operation while preserving
  the current coordinate order, boundary behavior, and restriction semantics.
- [x] Add Dart-versus-Rust parity fixtures, malformed-input coverage, bridge
  integration tests, and panic-safe typed error handling.
- [x] Verify formatting, Rust tests/lints, Flutter analysis/tests, Android ABI
  packaging, 16 KB native-library compatibility, and binary-size impact.
- [x] Measure the pilot on realistic workloads and retain Rust only where it
  produces a documented improvement over the Dart reference.
- [ ] Profile and then decide whether the compact PSGC index is the next Rust
  workload; do not duplicate the large dataset across ABI libraries.
- [ ] Instrument and optimize LiveKit call stages separately because network,
  Functions, permission, and ICE/TURN delay are outside the Rust compute path.
- [x] Keep Firebase SDK access, Node Functions, LiveKit/WebRTC, maps, GPS,
  permissions, Riverpod/UI, and the TSX admin outside the Rust core.
- [ ] Validate native ARMv7 execution on a real 32-bit device or emulator
  before treating the packaged low-end ABI as field-validated.
- [ ] Replace the pre-existing Android debug release certificate with
  production signing before distribution.
- [ ] Pin the Flutter SDK and Cargokit temporary runner dependency graph in CI,
  and preserve the documented custom Cargokit patches during FRB regeneration.

## Rust migration R2 - 2026-07-30

This bottom section is the sole active checklist for R2. All preceding entries
remain preserved as historical context and are not inputs to this phase.

- [x] Capture physical-device baselines for PSGC readiness, route/restriction
  evaluation, live proximity queries, and registration image preparation.
- [x] Add a deterministic compact PSGC artifact and native-owned indexed query
  engine without embedding the dataset in each Android ABI library.
- [x] Preserve exact PSGC ordering, codes, names, lookup behavior, and a Dart
  fallback; verify canonical counts and source/artifact hashes.
- [x] Replace repeated route polygon transfer with a versioned native
  restriction cache and one fused encoded-polyline conflict query.
- [x] Preserve route-selection order, boundary inclusion, malformed-input
  handling, original restriction index mapping, rollout controls, and Dart
  fallback behavior.
- [x] Add nearest-restriction, inside, and distance queries that reuse the same
  native cache while keeping GPS gating, hysteresis, cooldowns, alerts, and
  backend reporting in Dart.
- [x] Implement a file-path-based Rust registration image preparation
  experiment with bounded decode safeguards and exact orientation/crop/resize
  behavior; retain it only when physical-device measurements justify it.
- [x] Run Rust formatting/tests/lints, bridge generation checks, Dart
  formatting/analysis/tests, Android packaging checks, and physical-device
  integration/benchmark coverage.
- [x] Record retained and rejected R2 work, measurements, limitations, and
  rollback behavior in the matching bottom section of `done.md`.
