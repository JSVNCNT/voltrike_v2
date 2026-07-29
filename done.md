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
