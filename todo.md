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
