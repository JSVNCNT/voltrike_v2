# CONTEXT
- SYSTEM: Flutter/Riverpod/go_router mobile; Firebase Functions/Firestore/RTDB/Storage/FCM; React-Vite admin; LiveKit; Google Maps
- TARGET: Defense-ready complete ride; production behavior; unreleased.
- SOURCE: VolTrike screenshots are requirements; external screenshots are references.
- DEFERRED: Polygon editor redesign, validation, and release hardening.
- DEMO PATH: Request -> accept -> track -> arrive -> ride -> drop-off -> rate -> receipt.

# ARCHITECTURAL RULES (FOR SOL MEDIUM AUTOMATION)
1. Read only the topmost pending milestone block.
2. Inspect only files required by that milestone.
3. Preserve unrelated user changes and current architecture.
4. Implement every FIX, ADD, and HANDLE entry.
5. Run every VERIFY entry; never claim unexecuted validation.
6. Remove the milestone only when every DONE condition passes.
7. Append one telegraphic completion entry to `DONE.md`.
8. Record changed files, verification, and remaining deployment work.
9. On failure, retain the milestone and add one BLOCKED line.
10. Never store code, stack traces, or full command output here.
11. Halt after one completed or blocked milestone.

# MILESTONES (PENDING STATUS)

## M01 [ ] Booking routing and recovery
- FIX: Remove raw Navigator usage from booking lifecycle.
- ADD: Role/status coordinator above both navigation shells.
- HANDLE: Searching, assigned, arriving, onboard, completed, cancelled.
- DONE: Accept, tabs, back, restart restore correct screen.
- VERIFY: Router tests; passenger and driver resume checks.
- BLOCKED: Post-index assigned restart needs unlocked passenger device.

## M02 [ ] Unified driver location session
- CODE: Implemented; validation deferred by overnight constraint.
- FIX: Merge duplicate driver GPS providers and subscriptions.
- ADD: Single local state plus throttled RTDB heartbeat.
- HANDLE: Permission, resume, disconnect, offline, disposal.
- DONE: Driver marker survives active ride and navigation changes.
- VERIFY: Provider tests; fresh and resumed GPS checks.

## M03 [ ] Passenger route and ETA reliability
- CODE: Implemented; validation deferred by overnight constraint.
- FIX: Recalculate routes when driver position materially changes.
- ADD: Distance, deviation, and interval refresh thresholds.
- HANDLE: Missing GPS, route failure, status destination changes.
- DONE: Marker, polyline, distance, ETA remain synchronized.
- VERIFY: Route-key tests; moving-driver two-device check.

## M04 [ ] Ride lifecycle labels and actions
- CODE: Implemented; validation deferred by overnight constraint.
- FIX: Align visible labels with canonical booking statuses.
- ADD: One stage-to-copy/action presentation mapper.
- HANDLE: Hide Report/SOS before relevant active stages.
- DONE: Each role sees one valid primary action.
- VERIFY: State-mapper tests across every booking status.

## M05 [ ] Driver-controlled cash settlement
- CODE: Implemented; Functions deployment and validation pending.
- FIX: Remove passenger cash-paid completion dependency.
- ADD: Atomic driver cash-received and ride-completion operation.
- HANDLE: Retry, idempotency, disagreement, audit, availability release.
- DONE: Drop-off succeeds without passenger interaction.
- VERIFY: Function tests; repeated drop-off integration test.

## M06 [ ] Rating, receipts, and home return
- CODE: Implemented; validation deferred by overnight constraint.
- FIX: Route passenger to rating before receipt.
- ADD: Driver-specific receipt and earnings summary.
- HANDLE: Identity/photo fallback and rating permission failures.
- DONE: Both roles finish once and return home.
- VERIFY: Completion, rating, receipt, restoration integration tests.

## M07 [ ] Tracking screen UI restructuring
- CODE: Implemented; phone-size visual inspection pending.
- FIX: Keep required actions visible without scrolling.
- ADD: Half-map draggable sheet using VolTrike styling.
- ADD: Counterpart photo, name, verification, call, message.
- HANDLE: Compact, half, expanded sheet states.
- DONE: PDF-required information appears at every ride stage.
- VERIFY: Widget tests; phone-size visual inspection.

## M08 [ ] Reports and safe error presentation
- CODE: Implemented; Functions/rules deployment and validation pending.
- FIX: Repair callable submission and deployed permission parity.
- ADD: Role-specific concern types and contextual reasons.
- ADD: Central Firebase-to-domain error message mapper.
- HANDLE: TODA/developer visibility, duplicate submission, offline failure.
- DONE: Reports save; raw exceptions never reach users.
- VERIFY: Function, rules, widget, and admin visibility tests.

## M09 [ ] Incoming call lifecycle
- CODE: Implemented; Functions/rules deployment and LiveKit test pending.
- FIX: Stop routing incoming calls into tracking screens.
- ADD: Ringing, accepted, declined, ended, expired states.
- ADD: Incoming call screen with accept and decline.
- HANDLE: Duplicate taps, timeout, background notification, cleanup.
- DONE: Both roles join LiveKit only after acceptance.
- VERIFY: Call-state tests; foreground/background two-device calls.

## M10 [ ] Embedded driver navigation
- CODE: Implemented with the Google Navigation SDK; device checks pending.
- ADD: Pickup/destination selection based on ride stage.
- HANDLE: Invalid coordinates, GPS loss, quota, and SDK initialization errors.
- HANDLE: Continue heartbeat while embedded guidance is active.
- DONE: Correct in-app route opens and the active ride remains available.
- VERIFY: Pickup/drop-off guidance and background tracking checks.

## M11 [ ] History and dashboard UI
- CODE: Implemented; visual and provider validation pending.
- FIX: Remove duplicate shortcuts and rename Your Earnings.
- ADD: Paginated recent trips with expandable details.
- ADD: Counterpart identity, receipt, report access per trip.
- HANDLE: Empty, loading, legacy, and missing-photo states.
- DONE: Passenger and driver dashboards match PDF requirements.
- VERIFY: Provider and widget tests; role visual inspection.

## M12 [ ] Admin metrics and authority
- CODE: Implemented; Functions deployment and admin typecheck pending.
- FIX: Replace first-page totals with server aggregates.
- FIX: Search complete scoped datasets, not fetched pages.
- ADD: TODA earnings; developer platform metrics.
- ENFORCE: TODA-only routine driver and vehicle approvals.
- HANDLE: Developer suspension, audit, emergency oversight.
- DONE: Counts, metrics, search, permissions match each role.
- VERIFY: Function tests; admin TypeScript; both-role smoke checks.

## M13 [ ] Deployment parity and diagnostics
- CODE: Implemented; all deployments and smoke calls pending.
- ADD: Client, Functions, rules, and schema version diagnostics.
- FIX: Align deployed functions, indexes, and security rules.
- HANDLE: Region mismatch, stale client, missing callable.
- DONE: Defense devices report compatible deployed versions.
- VERIFY: Deployment smoke calls; report/rating permission checks.

## M14 [ ] Defense regression and evidence
- ADD: Two-role happy-path integration coverage.
- COVER: Accept, restart, tracking, settlement, rating, report, call.
- RUN: Flutter tests, Functions tests, admin typecheck.
- RUN: Two-device defense smoke test with embedded driver navigation.
- DONE: No critical failures; evidence recorded in `DONE.md`.
- VERIFY: Repeat clean-data demo from account login.

# COMPLETED STATUS
- Stored in `DONE.md`; do not load unless requested.
