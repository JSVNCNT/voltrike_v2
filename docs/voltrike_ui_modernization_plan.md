# VolTrike App-Wide UI Modernization Plan

## Status

- Architecture audit complete.
- The shared foundation and first app-wide modernization slice are implemented.
- This document is the durable context and TODO source for the modernization.
- Read `booking_flow_todo/MODERN_RIDE_TRACKING_UI.md` separately for the active
  ride-tracking bottom-sheet work that is already implemented.

## Goal

Modernize the passenger app, driver app, shared ride experiences, authentication,
profiles, and admin portal as one recognizable VolTrike product while preserving
all working booking, account, safety, communication, payment, rating, reporting,
navigation, and Firebase behavior.

The result should feel modern, calm, trustworthy, TNVS-specific, accessible, and
human-designed. It must not look like a generic AI-generated interface.

## Non-negotiable boundaries

1. This is a presentation and usability modernization.
2. Keep existing repositories, providers, controllers, callable functions,
   Firestore/RTDB behavior, route guards, role checks, and booking status rules.
3. Do not add, rename, reinterpret, or persist booking states for visual needs.
4. Keep passenger and driver data different where their jobs differ; share the
   visual structure rather than forcing identical dashboards.
5. Retain VolTrike's name, tricycle identity, Poppins typography on mobile, and
   dark-cyan/teal brand character.
6. Use Material 3 components and semantics on mobile.
7. Keep SOS visually distinct and accurately disclose its current behavior. Do
   not imply that external emergency services were contacted when they were not.
8. Preserve Google Maps, Waze, and system chooser behavior for driver navigation.
9. Do not revive unused legacy trip models, duplicate screens, or zero-byte
   placeholder widgets while modernizing the active UI.
10. Do not combine data values that only appear equivalent. In particular,
    driver earnings currently have multiple sources with different calculations.

## Product design direction

### Visual identity

- Main canvas: near-white, not pure gray and not a cyan wash.
- Primary navigation and strongest brand moments: dark cyan.
- Primary interactive color: accessible deep teal/cyan.
- Cards: white with a quiet border and restrained elevation.
- Typography: Poppins across mobile and admin for one product identity.
- Corners: mostly 12, 16, and 24 logical pixels; pills only for statuses,
  segmented controls, and genuinely compact actions.
- Icons: consistent Material symbols/icons with labels for important actions.
- Motion: short and functional; respect reduced-motion preferences.

### Proposed semantic color roles

| Role | Starting value | Use |
| --- | --- | --- |
| Canvas | `#F7F9FA` | Main mobile and admin background |
| Surface | `#FFFFFF` | Cards, sheets, dialogs |
| Brand dark | `#063B3C` | Navigation, immersive call surfaces |
| Primary action | `#006F73` | Text-bearing primary buttons |
| Brand accent | `#008B8B` | Icons, selected accents, non-text emphasis |
| Primary container | `#D8EFEF` | Selected tabs, subtle highlights |
| Main text | `#173234` | Headings and important values |
| Secondary text | `#557072` | Supporting information |
| Outline | `#D8E4E4` | Dividers, fields, card borders |
| Success | Semantic green | Completed and approved states |
| Warning | Semantic amber | Pending and review states |
| Destructive | Semantic red | Cancel, report escalation, SOS, suspension |

Final values must be contrast-tested before implementation. Do not place normal
white text on the current `#008B8B` when it fails the target contrast; use the
darker primary action color.

### What to avoid

- Decorative gradients, glassmorphism, glowing cards, floating color blobs, and
  excessive shadows.
- Oversized emojis, generic illustrations, or fake analytics.
- Making every surface and button a pill.
- Hiding important TNVS data behind decorative layouts.
- Color-only status communication.
- Meaningless dashboard charts where only current totals exist.
- Copy or visuals that imply artificial intelligence.

## Active architecture to preserve

### App foundation

- `lib/app/app.dart`
  - `MaterialApp.router`, current theme, and app-level media configuration.
- `lib/app/router.dart`
  - GoRouter destinations, account gates, active-booking recovery, role routes,
    rating, receipt, chat, and call entry points.
- `lib/core/theme/`
  - Existing Material 3 theme, Poppins typography, and VolTrike colors.
- `lib/features/common/presentation/screens/app_shell_screen.dart`
- `lib/features/common/presentation/widgets/app_bottom_navigation.dart`
  - Shared Home, Dashboard, Trips, and Profile shell for both roles.

### Booking and active rides

- `lib/features/driver/controllers/driver_booking_controller.dart`
- `lib/features/ride/tracking/services/ride_stage_presentation_service.dart`
- `lib/data/models/booking_state_machine.dart`
- Driver and passenger tracking screens and their existing callbacks.

The state machine and presentation policy remain the sources of truth. UI
components consume their outputs and must not duplicate lifecycle decisions.

### Authentication and access

- `lib/features/auth/presentation/controllers/splash_controller.dart`
- `lib/features/auth/presentation/widgets/account_status_gate.dart`
- `lib/features/auth/domain/account_access_policy.dart`
- Existing auth controllers, registration data provider, mapper, uploads, and
  email-verification flow.

### Admin

- `admin/src/App.tsx`
- `admin/src/admin-api.ts`
- `admin/src/types.ts`
- `admin/src/styles.css`

Firebase custom claims, Firestore role/TODA status, callable authorization, and
security rules remain unchanged and authoritative.

## Modernization backlog

### Phase 0 — Protect behavior before visual work

- [ ] Record the current passenger and driver happy paths with screenshots.
- [ ] Map every screen action to its existing callback/controller/repository.
- [ ] Add presentation-level regression coverage where a screen is currently
      risky to change.
- [ ] Confirm which existing dirty working-tree changes belong to the completed
      ride-tracking modernization before beginning this app-wide pass.
- [ ] Do not mix backend cleanup into UI commits.

### Phase 1 — Shared design system

- [x] Expand `AppTheme` into semantic component themes for cards, sheets,
      dialogs, segmented buttons, chips, navigation, icon buttons, snackbars,
      menus, dividers, progress indicators, and destructive actions.
- [ ] Introduce shared spacing, radius, elevation, icon-size, and duration tokens.
- [x] Replace raw colors with semantic roles in the modernized screens.
- [x] Create reusable page header, section header, status badge, metric tile,
      information row, action button, empty state, error state, loading state,
      identity header, trip row, and confirmation-dialog patterns.
- [x] Keep icon plus text for Call, Chat, Report, SOS, Cancel, and primary ride
      actions; icon-only controls require a tooltip and semantic label.
- [x] Remove or substantially relax the app-level 1.2 text-scale cap so larger
      accessibility text can work, then repair layouts that reveal overflow.
- [x] Apply Poppins and the same semantic tokens to the admin portal.

### Phase 2 — Mobile shell and navigation

- [ ] Keep the shared four-tab shell and active-booking interception.
- [x] Modernize the Material 3 bottom navigation with clear selected state,
      consistent labels, safe-area spacing, and role-appropriate destinations.
- [x] Standardize shared app bars and the modernized screens' page padding,
      loading, errors, and scroll behavior.
      scroll behavior.
- [ ] Keep active driver navigation as a small accessible map control that opens
      Google Maps, Waze, or the current chooser.
- [ ] Do not casually consolidate driver online toggles: Home and Dashboard
      currently use different operational paths.

### Phase 3 — Trip history and trip detail

- [x] Replace the current expandable/dropdown trip cards with a segmented
      `All / Completed / Cancelled` history.
- [x] Keep filtering local to the existing terminal-history collection unless
      performance evidence requires a repository change.
- [x] Group trips by Today, Yesterday, then a readable date/month.
- [x] Make the full row a clear 48dp-or-larger tap target.
- [x] Show the most useful row data: route summary, counterpart, time, fare, and
      labelled status.
- [x] Open a dedicated role-aware trip detail instead of expanding inline.
- [x] Completed passenger detail: route, driver/vehicle/TODA, fare/payment,
      receipt, rating state/action, report, and booking reference.
- [x] Completed driver detail: route, passenger, fare/earnings presentation,
      receipt, report, and booking reference.
- [x] Cancelled detail: route, cancellation reason/actor when available, time,
      reference, and report; never claim payment or completion.
- [x] Preserve incremental loading and existing terminal-state ordering.
- [x] Add semantic labels for status, amount, date, and row action.

Important existing presentation defect: passenger history currently offers a
receipt for every terminal trip, including cancelled trips, while the receipt
screen always says the trip and cash payment completed. The new detail routing
must correct that presentation without changing booking-state logic.

### Phase 4 — Passenger and driver dashboards

- [x] Build one shared dashboard composition:
      identity/greeting, primary status/task, metrics, financial summary,
      current/recent ride, and quick actions.
- [x] Keep passenger content role-specific:
      total/completed/cancelled trips, spending, average fare, current or recent
      ride, pending ratings, and reporting.
- [x] Keep driver content role-specific:
      availability, current ride, completed/cancelled trips, rating/count,
      earnings views, recent passenger feedback, and operational shortcuts.
- [x] Use responsive metric layouts instead of oversized isolated cards.
- [x] Do not invent trends or charts that the backend does not provide.
- [x] Label each driver earnings source accurately until its calculation
      semantics are intentionally unified outside this UI project.

### Phase 5 — Authentication, splash, and registration

- [x] Reuse the existing auth scaffold, logo, header, fields, overlay, validation,
      and button components as the modernization seam.
- [x] Use a restrained near-white auth layout with focused VolTrike branding.
- [x] Give every active auth field a persistent label; placeholders are
      supplementary.
- [x] Retain password visibility and add clear inline validation,
      recovery-friendly errors,
      and predictable keyboard/focus order.
- [x] Keep splash session restoration, active-booking recovery, account gates,
      email verification, suspension, and driver-review routing unchanged.
- [x] Give driver registration a visible accessible `Step 1 of 4` progression,
      upload checklist, completion states, and retry information.
- [ ] Present pending, rejected, suspended, and verification states distinctly
      when the underlying account data supports the distinction.
- [x] Do not present the placeholder verification-resend behavior as successful.

### Phase 6 — Profiles, settings, and legal

- [x] Create a shared identity header and grouped settings-row language.
- [x] Passenger profile: account status, contact data, ride statistics, safety
      contacts, settings, and accurately labelled profile-photo editing.
- [x] Driver profile: contact data, availability/approval, TODA, vehicle,
      credentials, safety contacts, rating, trips, and earnings.
- [ ] Keep emergency contact storage and callbacks; add confirmation before
      deletion.
- [ ] Move shared legal/about presentation out of driver-namespaced ownership
      while retaining compatible routes.
- [x] Remove hardcoded version strings from the modernized profile/settings
      surfaces rather than presenting stale versions.
- [x] Use friendly mapped errors rather than raw exception strings on the
      modernized profile and dashboard surfaces.
- [ ] Treat the current driver profile-photo source mismatch as a separate data
      issue; do not hide it with styling.

### Phase 7 — Rating, receipt, report, chat, and calls

- [x] Rating: retain idempotency, ownership/completion checks, optional comment,
      skip, and receipt redirect.
- [x] Present driver/trip identity and accessible selected-star semantics instead
      of emphasizing a raw booking ID or a giant emoji.
- [ ] Receipt: keep live booking updates, role-aware content, settlement dispute,
      reporting, driver acknowledgement, state clearing, and home navigation.
- [ ] Use the receipt only as completed-trip presentation.
- [x] Report: keep existing categories, details, submission payload, permissions,
      and disclosures; modernize the form/dialog and validation.
- [x] Chat: preserve repository, membership, message, typing, seen, and sound
      behavior; modernize header context, bubbles, composer, focus, and errors.
- [ ] Calls: preserve invitation expiry, accept/decline/end, permissions,
      LiveKit, ringtone cleanup, participant resolution, mute, and timers.
- [ ] Keep calls as a deliberate immersive dark-cyan exception, using solid or
      restrained tonal surfaces rather than decorative gradients.

### Phase 8 — Admin portal

- [ ] Break the monolithic `admin/src/App.tsx` presentation into a shell, shared
      components, and role/page modules without changing API payloads or auth.
- [ ] Introduce URL-addressable routes so refresh, back, and deep links preserve
      the current page and selected entity.
- [x] Keep one dark-cyan responsive sidebar; use clear destination labels,
      `aria-current`, desktop navigation, and a narrow-screen horizontal
      navigation treatment.
      labels, `aria-current`, desktop collapse, and a mobile drawer.
- [x] Add a consistent page header title and authenticated scope indicator.
      last-refreshed information.
- [x] Replace generic session decoration with useful operational context.
- [ ] Overview: retain current metrics and polling; show role-specific priorities
      without fabricated trends.
- [ ] TODAs: searchable status tabs plus list/detail review workspace; retain all
      registration fields and evidence links.
- [ ] Drivers: searchable/filterable list and accessible detail workspace for
      identity, TODA, vehicle, documents, ratings, trips, earnings, and allowed
      role actions.
- [ ] Driver ratings: immutable feedback, numeric plus star labels, complete
      context, current pagination, and refresh behavior.
- [ ] Ride operations: keyboard-openable rows and a detailed trip workspace for
      parties, route, lifecycle, payment, settlement, cancellation, and receipt.
- [ ] Reports: master/detail Open/Resolved/Dismissed workflow with action history.
- [ ] Safety: prominent open SOS queue with participant, ride, and available
      location context; never imply external dispatch.
- [ ] Coverage and restrictions: consistent list/editor and a non-pointer
      alternative for map boundary creation.
- [ ] Replace browser prompts/confirms with focus-trapped dialogs that identify
      the target, consequence, required reason, and final action.
- [ ] Keep destructive styling only for destructive actions.
- [ ] Add keyboard, responsive, type-check, component, and accessibility checks.

### Phase 9 — Accessibility and quality gate

- [ ] Minimum target size: 48dp mobile and 44px web.
- [ ] Support large text without clipping or hiding primary actions.
- [ ] Meet WCAG AA contrast for text and important controls.
- [ ] Add meaningful semantics/labels for maps, stars, status, icon buttons,
      segmented controls, sheets, dialogs, and trip rows.
- [ ] Use status icon/text in addition to color.
- [ ] Provide visible focus states and complete keyboard operation on admin.
- [ ] Use semantic headings, tables/lists, labels, live regions, and dialog focus.
- [ ] Respect reduced motion.
- [ ] Verify empty, loading, offline, permission-denied, legacy-data,
      missing-photo, long-name, and long-address states.
- [ ] Test phone sizes, large text, tablet/responsive widths, and admin desktop/
      narrow layouts.
- [ ] Run Flutter formatter, targeted tests, full `flutter analyze`, relevant
      Flutter tests, and admin build/type checks before calling a phase complete.

## Known architecture risks to keep visible

1. Driver Home and Dashboard online toggles are operationally different.
2. Driver earnings are calculated/read from multiple non-identical sources.
3. Driver photo editing updates `users.profileImage`, while Driver Profile reads
   `driver.profilePhotoUrl`.
4. Rejected drivers currently fall into a generic under-review presentation.
5. The under-review verification resend action is a placeholder.
6. The earnings route lacks the same driver gate pattern and expects route data.
7. Invalid shared chat/call arguments currently fall back to passenger shell,
   including possible driver entries.
8. Passenger settings use driver-namespaced legal screens.
9. Admin is one large conditional-rendered component without URL routing.
10. Admin safety dispatch is not an external emergency-service integration.
11. Some active list APIs support cursors while current admin UI reads only an
    initial page.
12. Legacy and unused trip/history placeholders must not be mistaken for the
    active architecture.

These are not permissions to change backend behavior during UI work. If a risk
blocks truthful or correct presentation, isolate it and request a separate
decision.

## Implementation sequence

1. Shared tokens and components.
2. Shell, app bars, and common states.
3. Trips and role-aware trip detail.
4. Passenger and driver dashboards.
5. Auth, splash, and registration.
6. Profiles, settings, and legal.
7. Rating, receipt, report, chat, and calls.
8. Admin shell and page-by-page modernization.
9. Accessibility, responsive, regression, and visual-quality pass.

Complete one phase or one coherent vertical slice at a time. Do not attempt a
single app-wide visual rewrite in one unreviewable change.

## Token-saving resume strategy

After context compaction or in a new session:

1. Read this file first.
2. Read only the current phase and its named active architecture files.
3. For active ride tracking, read
   `booking_flow_todo/MODERN_RIDE_TRACKING_UI.md`; do not re-audit that flow.
4. Inspect `git status --short`, then preserve unrelated user changes.
5. Continue from the first unchecked item in the current phase.
6. Reuse existing callbacks/controllers/repositories. Inspect deeper backend code
   only when the UI contract is genuinely unclear or a test fails.
7. Keep lifecycle truth in `BookingStateMachine`, ride-action truth in
   `RideStagePresentationService`, account truth in access policies/gates, and
   admin authority in existing callable functions and rules.
8. After each completed slice, update only its checklist entries and append a
   short decision/verification note below.
9. Never paste full command output or implementation code into this document.
10. Do not mark an item complete without running its stated validation.

## Decision and verification notes

- 2026-07-27: Read-only architecture audit completed across passenger, driver,
  shared auth/shell/trips/profile/rating/receipt/chat/calls, and admin.
- 2026-07-27: Chosen direction is near-white canvas plus dark-cyan VolTrike
  identity, restrained Material 3, role-aware consistency, and no AI-styled
  decoration.
- 2026-07-27: Trip history will use segmented filters and dedicated trip details,
  not inline dropdown expansion.
- 2026-07-27: No Flutter, admin, backend, Firebase, or business-logic code was
  changed while creating this plan.
- 2026-07-27: Implemented the shared Material 3 theme, removed the 1.2 text
  scaling cap, and added reusable dashboard/profile/settings/history components.
- 2026-07-27: Rebuilt passenger and driver history, trip detail, dashboard,
  profile, and settings presentation without changing repositories or lifecycle
  callbacks.
- 2026-07-27: Modernized rating, report, and ride-chat presentation while
  retaining idempotency, permissions, membership, typing, seen, sound, and
  submission behavior.
- 2026-07-27: Modernized the admin visual system, sign-in accessibility,
  navigation state, responsive layout, focus treatment, forms, rows, maps, and
  role-scope display without changing Firebase authorization or API payloads.
- 2026-07-27: Verification passed: admin production build, full Flutter analysis
  with no issues, and all 58 Flutter tests.
- 2026-07-27: Completed the dedicated mobile-auth redesign: solid dark-cyan
  brand band, restrained form surfaces, modern intro/sign-in/recovery,
  grouped passenger registration, accessible four-step driver registration,
  modern document selection, verification, review, suspension, and splash
  states. Controllers, validation, uploads, gates, and routing were retained.
- 2026-07-27: Added large-text and registration-progress widget coverage.
  Full analysis passed and all 60 Flutter tests passed.
